#!/usr/bin/env bash
set -euo pipefail

bundle_id="com.sumi.browser"
support_root="${SUMI_APP_SUPPORT_OVERRIDE:-$HOME/Library/Application Support/$bundle_id}"
legacy_support_root="$HOME/Library/Application Support/Sumi"
bundle_cache_root="$HOME/Library/Caches/$bundle_id"
legacy_cache_root="$HOME/Library/Caches/Sumi"
webkit_root="$HOME/Library/WebKit/$bundle_id"
database="$support_root/Sumi.sqlite"

size_kib() {
  if [[ -e "$1" ]]; then
    du -sk "$1" | awk '{print $1}'
  else
    printf '0\n'
  fi
}

file_bytes() {
  if [[ -f "$1" ]]; then
    stat -f '%z' "$1"
  else
    printf '0\n'
  fi
}

directory_count() {
  if [[ -d "$1" ]]; then
    find "$1" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d '[:space:]'
  else
    printf '0\n'
  fi
}

printf 'metric|value\n'
printf 'support_root_kib|%s\n' "$(size_kib "$support_root")"
printf 'legacy_support_root_kib|%s\n' "$(size_kib "$legacy_support_root")"
printf 'bundle_cache_root_kib|%s\n' "$(size_kib "$bundle_cache_root")"
printf 'legacy_cache_root_kib|%s\n' "$(size_kib "$legacy_cache_root")"
printf 'browser_database_bytes|%s\n' "$(file_bytes "$database")"
printf 'browser_database_wal_bytes|%s\n' "$(file_bytes "$database-wal")"
printf 'persistent_store_directories|%s\n' \
  "$(directory_count "$webkit_root/WebsiteDataStore")"
printf 'webextension_controller_directories|%s\n' \
  "$(directory_count "$webkit_root/WebExtensions")"
printf 'content_rule_lists_kib|%s\n' \
  "$(size_kib "$webkit_root/ContentRuleLists")"
printf 'webextensions_kib|%s\n' \
  "$(size_kib "$webkit_root/WebExtensions")"

if [[ -f "$database" ]]; then
  sqlite3 -readonly -separator '|' "$database" <<'SQL'
SELECT 'browser_database_page_bytes', page_size * page_count
FROM pragma_page_size, pragma_page_count;
SELECT 'browser_database_free_bytes', page_size * freelist_count
FROM pragma_page_size, pragma_freelist_count;
SELECT 'profiles', count(*) FROM profiles;
SELECT 'history_entries', count(*) FROM history_entries;
SELECT 'history_visits', count(*) FROM history_visits;
SELECT 'history_distinct_urls', count(DISTINCT url) FROM history_entries;
SELECT 'history_profile_url_bytes', coalesce(sum(length(url)), 0)
FROM history_entries;
SELECT 'history_global_url_bytes', coalesce(sum(length(url)), 0)
FROM (SELECT url FROM history_entries GROUP BY url);
SELECT 'history_extra_profile_url_rows', coalesce(sum(c - 1), 0)
FROM (SELECT count(*) AS c FROM history_entries GROUP BY url HAVING c > 1);
SQL

  while IFS= read -r profile_id; do
    profile_store="$webkit_root/WebsiteDataStore/$profile_id"
    printf 'profile_store_kib:%s|%s\n' "$profile_id" \
      "$(size_kib "$profile_store")"
    printf 'profile_network_cache_kib:%s|%s\n' "$profile_id" \
      "$(size_kib "$profile_store/NetworkCache")"
    printf 'profile_origins_kib:%s|%s\n' "$profile_id" \
      "$(size_kib "$profile_store/Origins")"
  done < <(
    sqlite3 -readonly "$database" \
      "SELECT lower(substr(hex(id),1,8)||'-'||substr(hex(id),9,4)||'-'||substr(hex(id),13,4)||'-'||substr(hex(id),17,4)||'-'||substr(hex(id),21,12)) FROM profiles ORDER BY 1;"
  )
fi

favicon_root="$support_root/Favicons/v3"
legacy_favicon_root="$support_root/Favicons/v2"
printf 'favicon_v3_kib|%s\n' "$(size_kib "$favicon_root")"
printf 'legacy_favicon_v2_kib|%s\n' "$(size_kib "$legacy_favicon_root")"
if [[ -d "$favicon_root" ]]; then
  find "$favicon_root" -type f -path '*/blobs/*' -exec stat -f '%z %N' {} + |
    awk '
      {
        size = $1
        path = $0
        sub(/^[0-9]+ /, "", path)
        parts = split(path, segment, "/")
        name = segment[parts]
        files += 1
        bytes += size
        if (!(name in seen)) {
          seen[name] = 1
          unique_files += 1
          unique_bytes += size
        }
      }
      END {
        print "favicon_blob_files|" files + 0
        print "favicon_unique_blobs|" unique_files + 0
        print "favicon_blob_bytes|" bytes + 0
        print "favicon_deduplicated_bytes|" unique_bytes + 0
        print "favicon_duplicate_bytes|" bytes - unique_bytes
      }
    '
fi
