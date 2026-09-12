-- fortigate.lua - Port 5514: FortiGate / FortiOS ログパーサー
-- フォーマット: key=value (logfmt) 形式
package.path = package.path .. ";/fluent-bit/scripts/?.lua"
local common = require("common")

function process(tag, timestamp, record)
    local out, raw, host_from = common.create_base_record(tag, timestamp, record, 5514, "s_fortigate")

    if raw == "" then return 1, timestamp, out end
    out["raw_message"] = raw

    local kv = common.parse_kv(raw)

    -- KV フィールドを出力レコードに展開する
    for k, v in pairs(kv) do
        out[k] = v
    end

    -- host の決定: devname > devid > host_from
    out["host"]      = kv["devname"] or kv["devid"] or (host_from ~= "" and host_from or nil)
    out["host_from"] = host_from ~= "" and host_from or out["host"]
    common.normalize_host_from(out)

    -- タイムスタンプ: date + time フィールドが揃っている場合に ISO 8601 に変換する
    local gen_ts
    if kv["date"] and kv["time"] then
        gen_ts = common.iso8601_to_unix(kv["date"] .. "T" .. kv["time"] .. "+09:00")
    end

    -- program: type/subtype (例: "utm/webfilter")
    if kv["type"] then
        out["program"] = kv["type"] .. (kv["subtype"] and ("/" .. kv["subtype"]) or "")
    end

    -- priority: level フィールドから変換する
    if kv["level"] then
        out["priority"] = common.get_priority(kv["level"])
    end

    -- message: msg フィールドを優先し、なければ log または生ログを使用する
    out["message"] = kv["msg"] or kv["log"] or raw

    -- FortiGate 特有のフィールドが存在すれば正常パース済みとみなす
    local is_fortigate = kv["devname"] or kv["devid"] or kv["type"] or kv["logid"]
                      or (kv["date"] and kv["time"])
    out["parse_type"] = is_fortigate and "FortiGate" or "FortiGate_FALLBACK"

    return 1, (gen_ts or timestamp), out
end
