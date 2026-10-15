#!/usr/bin/env python3
"""Configure Microsoft Entra Cloud Sync (AD -> Entra) through Microsoft Graph and wait for the
synced test users, then add them to the cloud group that holds the AVD role assignments.

Stdlib only. Runs on the Semaphore controller and calls Graph as the lab's service principal
(client-credentials flow) using ENTRA_TENANT_ID, ARM_CLIENT_ID and ARM_CLIENT_SECRET. The
principal needs the Graph application roles Organization.ReadWrite.All,
Application.ReadWrite.All, Synchronization.ReadWrite.All, User.ReadWrite.All and
Group.ReadWrite.All (scripts/create-service-principal.sh grants them).

Subcommands:
  prep       enable the tenant's directory-sync flag
  configure  create the AD2AAD service principal + jobs, enable password hash sync, start them
  assign     wait for N synced users, then add them to ENTRA_GROUP_ID
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

AD2AAD_TEMPLATE = "1a4721b3-e57f-4451-ae87-ef078703ec94"
GRAPH = "https://graph.microsoft.com"
env = os.environ.get


def call(method, url, token, body=None, ok=(200, 201, 202, 204)):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:800]
        if e.code in ok:
            return {}
        sys.exit(f"{method} {url} -> HTTP {e.code}: {detail}")


def get_token():
    form = urllib.parse.urlencode({
        "grant_type": "client_credentials",
        "client_id": env("ARM_CLIENT_ID"),
        "client_secret": env("ARM_CLIENT_SECRET"),
        "scope": GRAPH + "/.default",
    }).encode()
    url = f"https://login.microsoftonline.com/{env('ENTRA_TENANT_ID')}/oauth2/v2.0/token"
    try:
        with urllib.request.urlopen(urllib.request.Request(url, data=form), timeout=60) as r:
            return json.loads(r.read())["access_token"]
    except urllib.error.HTTPError as e:
        err = json.loads(e.read().decode(errors="replace") or "{}")
        sys.exit("token request failed: %s" % str(err.get("error_description", err))[:400])


def prep(tok):
    org = call("GET", f"{GRAPH}/beta/organization", tok)["value"][0]
    if org.get("onPremisesSyncEnabled") is True:
        print("directory sync already enabled")
        return
    call("PATCH", f"{GRAPH}/beta/organization/{org['id']}", tok, {"onPremisesSyncEnabled": True})
    print("enabled directory sync for the tenant")


def find_sp(tok, name):
    q = urllib.parse.quote(f"displayName eq '{name}'")
    found = call("GET", f"{GRAPH}/beta/servicePrincipals?$filter={q}", tok).get("value", [])
    return found[0]["id"] if found else None


def find_or_create_sp(tok, name):
    sp = find_sp(tok, name)
    if sp:
        return sp
    res = call("POST", f"{GRAPH}/beta/applicationTemplates/{AD2AAD_TEMPLATE}/instantiate", tok,
               {"displayName": name})
    # The response shape differs between API versions, so look the principal up by name.
    sp = (res.get("servicePrincipal") or {}).get("id") or (res.get("servicePrincipal") or {}).get("objectId")
    for _ in range(12):
        sp = sp or find_sp(tok, name)
        if sp:
            return sp
        time.sleep(10)
    sys.exit("the AD2AAD service principal did not appear: " + json.dumps(res)[:400])


def configure(tok):
    domain = env("AD_DOMAIN")
    sp = find_or_create_sp(tok, domain)
    base = f"{GRAPH}/beta/servicePrincipals/{sp}/synchronization"
    # Retry: a new service principal can take a minute to become usable.
    for attempt in range(12):
        try:
            call("PUT", base + "/secrets", tok, {"value": [
                {"key": "AppKey", "value": json.dumps({"appKeyScenario": "AD2AADPasswordHash"})},
                {"key": "Domain", "value": json.dumps({"domain": domain})},
            ]})
            break
        except SystemExit as e:
            if attempt == 11:
                raise
            print("secrets not ready yet:", str(e)[:200])
            time.sleep(20)
    # A job's templateId differs from what was requested, so match on the id prefix.
    existing = call("GET", base + "/jobs", tok).get("value", [])
    ids = {}
    for tpl in ("AD2AADProvisioning", "AD2AADPasswordHash"):
        match = [j for j in existing if j["id"].startswith(tpl + ".")]
        ids[tpl] = match[0]["id"] if match else call(
            "POST", base + "/jobs", tok, {"templateId": tpl})["id"]
        print("job", tpl, ids[tpl])
    prov = ids["AD2AADProvisioning"]
    schema = call("GET", f"{base}/jobs/{prov}/schema", tok)
    wanted = {"provision active directory users", "provision active directory inetorgpersons"}
    mapping = {
        "defaultValue": None, "exportMissingReferences": False, "flowBehavior": "FlowWhenChanged",
        "flowType": "Always", "matchingPriority": 0, "targetAttributeName": "CredentialData",
        "source": {"expression": "[PasswordHash]", "name": "PasswordHash", "type": "Attribute",
                   "parameters": []},
    }
    changed = False
    for rule in schema.get("synchronizationRules", []):
        for om in rule.get("objectMappings", []):
            if om.get("name", "").lower() in wanted and not any(
                    a.get("targetAttributeName") == "CredentialData"
                    for a in om.get("attributeMappings", [])):
                om["attributeMappings"].append(mapping)
                changed = True
    if changed:
        call("PUT", f"{base}/jobs/{prov}/schema", tok, schema)
        print("added the CredentialData (password hash) mapping")
    for job in ids.values():
        call("POST", f"{base}/jobs/{job}/start", tok)
        print("started", job)


def assign(tok):
    want = int(env("TEST_USER_COUNT"))
    suffix = "@" + env("ENTRA_DOMAIN").lower()
    group = env("ENTRA_GROUP_ID")
    deadline = time.time() + int(env("SYNC_TIMEOUT", "2400"))
    synced = {}
    while time.time() < deadline:
        tok = get_token()
        url = (f"{GRAPH}/v1.0/users?$filter=startswith(userPrincipalName,'testuser')"
               "&$select=id,userPrincipalName,onPremisesSyncEnabled&$top=999")
        synced = {}
        while url:
            page = call("GET", url, tok)
            for u in page.get("value", []):
                if u.get("onPremisesSyncEnabled") and u["userPrincipalName"].lower().endswith(suffix):
                    synced[u["userPrincipalName"]] = u["id"]
            url = page.get("@odata.nextLink")
        print(f"{len(synced)}/{want} test users synced")
        if len(synced) >= want:
            break
        time.sleep(60)
    else:
        sys.exit("timed out waiting for the users to sync")
    members = set()
    url = f"{GRAPH}/v1.0/groups/{group}/members?$select=id&$top=999"
    while url:
        page = call("GET", url, tok)
        members |= {m["id"] for m in page.get("value", [])}
        url = page.get("@odata.nextLink")
    todo = [i for i in synced.values() if i not in members]
    for n in range(0, len(todo), 20):
        chunk = todo[n:n + 20]
        call("PATCH", f"{GRAPH}/v1.0/groups/{group}", tok, {
            "members@odata.bind": [f"{GRAPH}/v1.0/directoryObjects/{i}" for i in chunk]})
    print(f"added {len(todo)} synced users to the group ({len(members)} already members)")


if __name__ == "__main__":
    {"prep": prep, "configure": configure, "assign": assign}[sys.argv[1]](get_token())
