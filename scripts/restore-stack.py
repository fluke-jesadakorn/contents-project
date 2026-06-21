#!/usr/bin/env python3
"""Re-bootstrap n8n stack after volume wipe.

Uses n8n CLI (`import:credentials`, `import:workflow`) via docker exec —
no API key needed. Reads secrets from .env.

Steps:
  1. Create MinIO bucket that flows expect (epsx-contracts)
  2. Build creds JSON in n8n's expected shape → import via CLI
  3. Read assigned credential IDs from DB → remap in workflow JSONs
  4. Import workflows via CLI with --activeState=fromJson
  5. Verify

The workflow JSON files in n8n/flows/ reference OLD credential IDs from
the pre-wipe n8n DB. After CLI import, n8n generates NEW IDs, so we
remap old_id → new_id inside the workflow JSON before importing.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = ROOT / ".env"
N8N_CONTAINER = "contract-n8n"
PG_HOST = "localhost"
PG_PORT = 55432
PG_USER = "contract"
PG_DB_N8N = "n8n"

FLOW_FILES = [
    ROOT / "n8n/flows/03-docs-hub.json",
    ROOT / "n8n/flows/04-docs-admin.json",
]

# Old credential IDs that flows reference (from CREDENTIAL-AUDIT.md
# and a parse of the workflow JSON files).
OLD_CRED_IDS = {
    "regb87eec1e08a5cce3": "postgres",          # PG Contracts
    "LNHDR8F94CE3AA25E4B8E823C70": "httpHeaderAuth",  # LINE Bearer
    "minio-creds-epsx": "s3",                   # MinIO
}


def load_env():
    env = {}
    for line in ENV_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def pg(query):
    """Run SQL via psql in the postgres container."""
    return subprocess.run(
        ["docker", "exec", "contract-postgres", "psql",
         "-U", PG_USER, "-d", PG_DB_N8N, "-tA", "-c", query],
        capture_output=True, text=True,
    )


def n8n_cli(*args, capture=True):
    """Run n8n CLI inside the n8n container."""
    cmd = ["docker", "exec", N8N_CONTAINER, "n8n", *args]
    return subprocess.run(cmd, capture_output=capture, text=True)


def ensure_minio_bucket(bucket, env):
    print(f"\n[1/5] MinIO bucket '{bucket}'...")
    subprocess.run(
        ["docker", "exec", "contract-minio", "mc", "alias", "set", "local",
         "http://localhost:9000", env["MINIO_ROOT_USER"], env["MINIO_ROOT_PASSWORD"]],
        capture_output=True, text=True,
    )
    res = subprocess.run(
        ["docker", "exec", "contract-minio", "mc", "ls", f"local/{bucket}"],
        capture_output=True, text=True,
    )
    if res.returncode == 0:
        print(f"  ✓ already exists")
        return
    res = subprocess.run(
        ["docker", "exec", "contract-minio", "mc", "mb", f"local/{bucket}"],
        capture_output=True, text=True,
    )
    if res.returncode != 0 and "already exists" not in res.stdout + res.stderr:
        print(f"  ✗ create failed: {res.stderr}")
        sys.exit(1)
    subprocess.run(
        ["docker", "exec", "contract-minio", "mc", "anonymous",
         "set", "download", f"local/{bucket}"],
        capture_output=True, text=True,
    )
    print(f"  ✓ created")


def get_owner_user_id():
    """Get the user ID of admin@local.test (set up at first boot)."""
    res = pg("SELECT id FROM \"user\" WHERE email = 'admin@local.test';")
    if res.returncode != 0 or not res.stdout.strip():
        print(f"  ✗ no owner found in n8n DB: {res.stderr}")
        sys.exit(1)
    uid = res.stdout.strip()
    print(f"  owner user id: {uid}")
    return uid


def build_credentials(env):
    """Build n8n-format credentials JSON (id auto-generated; CLI requires it)."""
    import uuid
    return [
        {
            "id": str(uuid.uuid4()),
            "name": "PG Contracts - localhost:5432",
            "type": "postgres",
            "data": {
                "host": "host.docker.internal",
                "port": 55432,
                "database": env["POSTGRES_DB"],
                "user": env["POSTGRES_USER"],
                "password": env["POSTGRES_PASSWORD"],
                "ssl": "disable",
            },
        },
        {
            "id": str(uuid.uuid4()),
            "name": "LINE Bearer Auth",
            "type": "httpHeaderAuth",
            "data": {
                "name": "Authorization",
                "value": f"Bearer {env['LINE_CHANNEL_ACCESS_TOKEN']}",
            },
        },
        {
            "id": str(uuid.uuid4()),
            "name": "MinIO Contracts",
            "type": "s3",
            "data": {
                "endpoint": "contract-minio:9000",
                "region": "us-east-1",
                "accessKeyId": env["MINIO_ROOT_USER"],
                "secretAccessKey": env["MINIO_ROOT_PASSWORD"],
                "forcePathStyle": True,
            },
        },
    ]


def import_credentials(creds, user_id):
    """Write creds JSON to a temp dir in the n8n container, run CLI import."""
    print("\n[2/5] Import credentials via CLI...")
    tmpdir = "/tmp/n8n-restore-creds"
    # Clean previous
    subprocess.run(["docker", "exec", N8N_CONTAINER, "rm", "-rf", tmpdir],
                   capture_output=True)
    subprocess.run(["docker", "exec", N8N_CONTAINER, "mkdir", "-p", tmpdir],
                   capture_output=True)
    creds_path = f"{tmpdir}/creds.json"
    payload = json.dumps(creds).encode()
    subprocess.run(
        ["docker", "exec", "-i", N8N_CONTAINER, "sh", "-c",
         f"cat > {creds_path}"],
        input=payload, capture_output=True,
    )
    res = n8n_cli("import:credentials", f"--input={creds_path}",
                  f"--userId={user_id}")
    if res.returncode != 0:
        print(f"  ✗ import failed:\n{res.stderr or res.stdout}")
        sys.exit(1)
    print(f"  ✓ imported")


def read_new_cred_ids():
    """Read new credential IDs from DB, return list of (name, id)."""
    res = pg("SELECT name, id FROM credentials_entity ORDER BY name;")
    if res.returncode != 0:
        print(f"  ✗ read failed: {res.stderr}")
        sys.exit(1)
    creds = []
    for line in res.stdout.strip().splitlines():
        if "|" in line:
            name, cid = line.split("|", 1)
            creds.append((name.strip(), cid.strip()))
    return creds


def make_id_map():
    """Map old credential IDs (from workflow JSON) to new IDs (just imported)."""
    new_creds = read_new_cred_ids()
    print(f"  new creds: {new_creds}")
    by_name = {name: cid for name, cid in new_creds}

    # OLD_CRED_IDS maps old_id → "logical type"
    # Map logical type → expected credential name (new)
    logical_to_name = {
        "postgres": "PG Contracts - localhost:5432",
        "httpHeaderAuth": "LINE Bearer Auth",
        "s3": "MinIO Contracts",
    }

    id_map = {}
    for old_id, logical in OLD_CRED_IDS.items():
        target_name = logical_to_name[logical]
        new_id = by_name.get(target_name)
        if not new_id:
            print(f"  ✗ no credential named '{target_name}' in DB")
            sys.exit(1)
        id_map[old_id] = new_id
        print(f"    {old_id} ({logical}) → {new_id}")
    return id_map


def remap_flow(flow, id_map):
    """Recursively replace old cred IDs in flow JSON."""
    raw = json.dumps(flow)
    for old, new in id_map.items():
        raw = raw.replace(f'"id": "{old}"', f'"id": "{new}"')
        raw = raw.replace(f'"id":"{old}"', f'"id":"{new}"')
    return json.loads(raw)


def import_workflow(path, user_id, id_map):
    """Build a remapped flow in n8n container, import via CLI (inactive).
    Then publish via `publish:workflow` to activate."""
    print(f"  • {path.name}")
    flow = json.loads(path.read_text())
    flow = remap_flow(flow, id_map)

    # Strip version fields — n8n will regenerate from current nodes
    for k in ("activeVersionId", "activeVersion", "versionId", "versionCounter",
              "triggerCount", "shared", "tags", "checksum"):
        flow.pop(k, None)
    # Force inactive on import (we'll publish after)
    flow["active"] = False

    tmpdir = "/tmp/n8n-restore-flows"
    subprocess.run(["docker", "exec", N8N_CONTAINER, "mkdir", "-p", tmpdir],
                   capture_output=True)
    in_path = f"{tmpdir}/{path.name}"
    payload = json.dumps(flow).encode()
    subprocess.run(
        ["docker", "exec", "-i", N8N_CONTAINER, "sh", "-c",
         f"cat > {in_path}"],
        input=payload, capture_output=True,
    )

    res = n8n_cli("import:workflow", f"--input={in_path}",
                  f"--userId={user_id}")
    if res.returncode != 0:
        print(f"      ✗ import failed:\n{res.stderr or res.stdout}")
        sys.exit(1)
    # Find the workflow ID by name in DB
    expected_name = flow["name"]
    q = f"SELECT id FROM workflow_entity WHERE name = '{expected_name.replace(chr(39), chr(39)+chr(39))}';"
    res = pg(q)
    wf_id = res.stdout.strip()
    if not wf_id:
        print(f"      ✗ imported but not found in DB")
        sys.exit(1)
    print(f"      ✓ imported (id={wf_id}, inactive)")

    # Publish/activate
    pub = n8n_cli("publish:workflow", f"--id={wf_id}")
    if pub.returncode != 0:
        print(f"      ✗ publish failed: {pub.stderr or pub.stdout}")
        return False
    print(f"      ✓ published (active)")
    return True


def verify():
    print("\n[5/5] Verify...")
    # Workflows
    res = pg("SELECT name, id, active FROM workflow_entity ORDER BY name;")
    print("  workflows:")
    for line in res.stdout.strip().splitlines():
        if "|" in line:
            name, wid, active = line.split("|")
            mark = "●" if active == "t" else "○"
            print(f"    {mark} {name.strip()} (id={wid.strip()}, active={active.strip()})")
    # Credentials
    res = pg("SELECT name, type FROM credentials_entity ORDER BY name;")
    print("  credentials:")
    for line in res.stdout.strip().splitlines():
        if "|" in line:
            name, ctype = line.split("|")
            print(f"    • {name.strip()} ({ctype.strip()})")
    # MinIO buckets
    res = subprocess.run(
        ["docker", "exec", "contract-minio", "mc", "ls", "local"],
        capture_output=True, text=True,
    )
    print(f"  MinIO buckets:\n{res.stdout}")


def main():
    env = load_env()
    print(f"Loaded {len(env)} env vars from {ENV_FILE}")

    # Step 1: MinIO bucket
    ensure_minio_bucket("epsx-contracts", env)

    # Step 2: get owner user id (created at first boot)
    print("\n[2/5] Resolve owner user id...")
    user_id = get_owner_user_id()

    # Step 3: build + import credentials
    creds = build_credentials(env)
    import_credentials(creds, user_id)

    # Step 4: read new IDs, build mapping
    print("\n[3/5] Remap credential IDs in workflow JSONs...")
    id_map = make_id_map()

    # Step 5: import + activate workflows
    print("\n[4/5] Import workflows...")
    for path in FLOW_FILES:
        import_workflow(path, user_id, id_map)

    verify()
    print("\n✓ done")


if __name__ == "__main__":
    main()