-- syslog_standard.lua - 標準 Syslog パーサー (RFC 5424 / RFC 3164 / YAMAHA RTX / IX ルーター)
-- 対象ポート: 514 (UDP/TCP), 2514 (TCP octet-counted), 4514 (UDP/TCP)
package.path = package.path .. ";/fluent-bit/scripts/?.lua"
local common = require("common")

function process(tag, timestamp, record)
    -- タグからデフォルトポートとソース名を決定する
    local default_port, default_source
    if tag:find("rfc3164") then
        default_port, default_source = 4514, "s_rfc3164"
    elseif tag:find("octet") then
        default_port, default_source = 2514, "s_rfc5424"
    else
        default_port, default_source = 514,  "s_rfc5424"
    end

    local out, raw, host_from, port, transport =
        common.create_base_record(tag, timestamp, record, default_port, default_source)

    if raw == "" then return 1, timestamp, out end
    out["raw_message"] = raw

    -- =========================================================================
    -- 1. RFC 5424 を試みる
    -- =========================================================================
    local r5 = common.parse_rfc5424(raw)
    if r5 then
        out["facility"]        = r5.facility
        out["priority"]        = r5.priority
        out["host"]            = r5.host or host_from
        out["program"]         = r5.program
        out["pid"]             = r5.pid
        out["msgid"]           = r5.msgid
        out["structured_data"] = r5.structured_data
        out["@timestamp"]      = r5.ts
        out["source"]          = string.format("s_rfc5424/%d/%s", port, transport)
        out["parse_type"]      = r5.parse_type or "RFC5424"
        common.normalize_host_from(out)

        -- YAMAHA RTX などの [TAG] をメッセージ先頭から program として抽出する
        if r5.message and not out["program"] then
            local ytag = r5.message:match("^%[([%w_%-]+)%]")
            if ytag then out["program"] = ytag end
        end

        out["message"] = r5.message and common.trim(r5.message) or raw
        return 1, (r5.gen_ts or timestamp), out
    end

    -- =========================================================================
    -- 2. RFC 3164 / YAMAHA RTX にフォールバック
    -- =========================================================================
    local r3 = common.parse_rfc3164(raw)
    if r3 then
        out["facility"]   = r3.facility
        out["priority"]   = r3.priority
        out["source"]     = string.format("s_rfc3164/%d/%s", port, transport)
        out["pid"]        = r3.pid
        out["parse_type"] = r3.parse_type or "RFC3164"

        -- YAMAHA [TAG] 形式の補正と host / program の設定
        local msg = common.extract_yamaha_tag(r3.host, r3.message, host_from, out)
        out["program"] = out["program"] or r3.program
        common.normalize_host_from(out)

        -- message 先頭の [TAG] から program を補完する
        if msg and not out["program"] then
            local ytag = msg:match("^%[([%w_%-]+)%]")
            if ytag then out["program"] = ytag end
        end

        out["message"] = msg and common.trim(msg) or raw
        return 1, (r3.gen_ts or timestamp), out
    end

    -- =========================================================================
    -- 3. 両パーサーが失敗した場合: FALLBACK
    -- =========================================================================
    out["parse_type"] = (default_port == 4514) and "RFC3164_FALLBACK" or "RFC5424_FALLBACK"
    return 1, timestamp, out
end
