-- panos.lua - Port 5515: Palo Alto PAN-OS ログパーサー
-- フォーマット: CSV (PAN-OS syslog 形式)
package.path = package.path .. ";/fluent-bit/scripts/?.lua"
local common = require("common")

function process(tag, timestamp, record)
    local out, raw, host_from = common.create_base_record(tag, timestamp, record, 5515, "s_panos")

    if raw == "" then return 1, timestamp, out end
    out["raw_message"] = raw
    out["program"]     = "paloalto_panos"

    -- RFC 5424 スタイルのヘッダー: "YYYY-MM-DDTHH:MM:SS+TZ host - - - - csv_data"
    local ts_str, phost, csv =
        raw:match("([0-9]+-[0-9]+-[0-9]+T[^%s]+) +([^%s]+) +%- +%- +%- +%- +(.*)")

    local gen_ts
    if ts_str then
        gen_ts     = common.iso8601_to_unix(ts_str)
        out["host"] = phost
    else
        csv = raw
    end
    common.normalize_host_from(out)

    local fields = common.parse_csv(csv)
    if #fields < 5 then
        out["message"]    = csv
        out["parse_type"] = "PAN-OS_FALLBACK"
        return 1, (gen_ts or timestamp), out
    end

    -- 共通フィールドの設定 (フィールド番号は PAN-OS syslog 仕様に従う)
    local lt = fields[4]   -- log type (SYSTEM / THREAT / TRAFFIC 等)
    out["type"]           = lt
    out["subtype"]        = fields[5]
    out["serial"]         = fields[3]
    out["receive_time"]   = fields[2]
    out["time_generated"] = fields[7]

    -- time_generated が取得できた場合はそちらのタイムスタンプを優先する
    if fields[7] and fields[7] ~= "" then
        local tg_ts = common.iso8601_to_unix(fields[7])
        if tg_ts then gen_ts = tg_ts end
    end

    -- ログタイプ別のフィールド設定
    if lt == "SYSTEM" and #fields >= 16 then
        out["vsys"]        = fields[8]
        out["eventid"]     = fields[9]
        out["module"]      = fields[13]
        out["priority"]    = common.get_priority(fields[14])
        out["device_name"] = fields[16]
        out["message"]     = (fields[15] and fields[15] ~= "") and fields[15] or csv

    elseif lt == "THREAT" and #fields >= 29 then
        out["src"]      = fields[8]
        out["dst"]      = fields[9]
        out["rule"]     = fields[12]
        out["app"]      = fields[15]
        out["action"]   = fields[24]
        out["threatid"] = fields[26]
        out["priority"] = common.get_priority(fields[28])
        out["message"]  = csv

    elseif lt == "TRAFFIC" and #fields >= 29 then
        out["src"]     = fields[8]
        out["dst"]     = fields[9]
        out["rule"]    = fields[12]
        out["app"]     = fields[15]
        out["sport"]   = fields[18]
        out["dport"]   = fields[19]
        out["proto"]   = fields[23]
        out["action"]  = fields[24]
        out["bytes"]   = fields[25]
        out["packets"] = fields[28]
        out["message"] = csv

    else
        out["message"] = csv
    end

    out["parse_type"] = "PAN-OS"
    return 1, (gen_ts or timestamp), out
end
