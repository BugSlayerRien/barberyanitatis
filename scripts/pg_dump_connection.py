#!/usr/bin/env python3
"""Resolve libpq env vars for pg_dump without printing secrets.

GitHub-hosted runners are IPv4-only. Supabase Direct (db.<ref>.supabase.co)
is IPv6-only unless the IPv4 add-on is enabled. Session pooler port 5432 is
IPv4-reachable and supports pg_dump; transaction pooler port 6543 does not.
"""
from __future__ import annotations

import json
import os
import socket
import sys
from urllib.parse import parse_qs, unquote, urlparse


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def trim_url(raw: str) -> str:
    value = (raw or "").strip().replace("\r", "")
    if (value.startswith('"') and value.endswith('"')) or (
        value.startswith("'") and value.endswith("'")
    ):
        value = value[1:-1].strip()
    return value


def parse_pg_url(raw: str):
    url = trim_url(raw)
    if not url:
        return None
    parsed = urlparse(url)
    if parsed.scheme not in ("postgres", "postgresql"):
        fail("DB URL must start with postgresql://")
    if not parsed.hostname:
        fail("DB URL is missing a hostname.")
    query = parse_qs(parsed.query)
    port = parsed.port or 5432
    user = unquote(parsed.username or "")
    password = unquote(parsed.password or "")
    database = unquote((parsed.path or "").lstrip("/") or "postgres")
    sslmode = (query.get("sslmode") or ["require"])[0] or "require"
    return {
        "host": parsed.hostname,
        "port": int(port),
        "user": user,
        "password": password,
        "database": database,
        "sslmode": sslmode,
    }


def ipv4_addrs(host: str, port: int) -> list[str]:
    try:
        infos = socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_STREAM)
    except socket.gaierror:
        return []
    addrs = []
    for info in infos:
        addr = info[4][0]
        if addr not in addrs:
            addrs.append(addr)
    return addrs


def ipv6_addrs(host: str, port: int) -> list[str]:
    try:
        infos = socket.getaddrinfo(host, port, socket.AF_INET6, socket.SOCK_STREAM)
    except socket.gaierror:
        return []
    addrs = []
    for info in infos:
        addr = info[4][0]
        if addr not in addrs:
            addrs.append(addr)
    return addrs


def project_ref_from_direct_host(host: str) -> str:
    host = (host or "").lower()
    if host.startswith("db.") and host.endswith(".supabase.co"):
        return host[len("db.") : -len(".supabase.co")]
    return ""


def shlex_quote(value: str) -> str:
    return "'" + value.replace("'", "'\"'\"'") + "'"


def emit(env: dict[str, str]) -> None:
    for key, value in env.items():
        print(f"export {key}={shlex_quote(value)}")


def pooler_host_from_env() -> str:
    explicit = os.environ.get("SUPABASE_POOLER_HOST", "").strip()
    if explicit:
        return explicit.split("/")[0].split(":")[0]
    db_url = parse_pg_url(os.environ.get("DB_URL", "") or "")
    if db_url and "pooler.supabase.com" in db_url["host"] and db_url["port"] != 6543:
        return db_url["host"]
    return ""


def main() -> None:
    raw = os.environ.get("DB_DIRECT_URL", "")
    parsed = parse_pg_url(raw)
    if not parsed:
        fail(
            "Set DB_DIRECT_URL to the Supabase direct Postgres URL "
            "(db.<project-ref>.supabase.co:5432, sslmode=require)."
        )
    if parsed["port"] == 6543 or ":6543" in trim_url(raw):
        fail(
            "DB_DIRECT_URL looks like the transaction pooler (port 6543). "
            "pg_dump needs port 5432 (direct host or session pooler)."
        )
    if not parsed["password"]:
        fail("DB_DIRECT_URL is missing a password.")

    host = parsed["host"]
    user = parsed["user"]
    ref = project_ref_from_direct_host(host)
    is_direct = bool(ref)
    is_session_pooler = ("pooler.supabase.com" in host) and parsed["port"] == 5432

    if is_direct:
        # Direct role is "postgres". postgres.<ref> is the pooler username.
        if user.startswith("postgres."):
            if not ref:
                ref = user.split(".", 1)[1]
            user = "postgres"
        elif not user:
            user = "postgres"

    kind = "direct"
    hostaddr = ""
    v4 = ipv4_addrs(host, parsed["port"])
    v6 = ipv6_addrs(host, parsed["port"])

    if is_direct and not v4:
        pooler_host = pooler_host_from_env()
        if not pooler_host:
            fail(
                "Direct host "
                + host
                + " has no IPv4 address (Supabase Direct is IPv6-only). "
                "This network cannot reach it. Set SUPABASE_POOLER_HOST to the "
                "session pooler hostname (*.pooler.supabase.com) or set DB_URL "
                "to the session pooler URL on port 5432. Do not use port 6543."
            )
        if user == "postgres" and ref:
            pooler_user = "postgres." + ref
        elif user.startswith("postgres."):
            pooler_user = user
        else:
            pooler_user = user
        print(
            "Direct host is IPv6-only (no A record); GitHub-hosted runners "
            "cannot use it. Using session pooler on port 5432.",
            file=sys.stderr,
        )
        host = pooler_host
        user = pooler_user
        parsed["port"] = 5432
        kind = "session-pooler"
        hostaddr = ""
    elif v4:
        hostaddr = v4[0]
        kind = "direct-ipv4" if is_direct else (
            "session-pooler" if is_session_pooler else "postgres"
        )
        if not is_direct:
            hostaddr = ""
    elif v6:
        kind = "direct-ipv6" if is_direct else "postgres"
    else:
        fail(f"Could not resolve {host}.")

    env = {
        "PGHOST": host,
        "PGPORT": str(parsed["port"]),
        "PGUSER": user,
        "PGDATABASE": parsed["database"] or "postgres",
        "PGSSLMODE": "require",
        "PGGSSENCMODE": "disable",
        "PGCONNECT_TIMEOUT": os.environ.get("PGCONNECT_TIMEOUT", "20"),
        "PGPASSWORD": parsed["password"],
        "BACKUP_CONN_KIND": kind,
    }
    if hostaddr:
        env["PGHOSTADDR"] = hostaddr
    if "--json" in sys.argv:
        json.dump(env, sys.stdout)
        sys.stdout.write("\n")
    else:
        emit(env)
    print(
        f"pg_dump connection: {kind} host={host} port={parsed['port']} "
        f"user={user} sslmode=require"
        + (f" hostaddr={hostaddr}" if hostaddr else ""),
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
