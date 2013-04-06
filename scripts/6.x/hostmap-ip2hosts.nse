description = [[
Finds hostnames that resolve to the target's IP address by querying the online database:
* http://www.ip2hosts.com ( Bing Search Results )

The script is in the "external" category because it sends target IPs to a third party in order to query their database.
]]

---
-- @args hostmap.prefix If set, saves the output for each host in a file
-- called "<prefix><target>". The file contains one entry per line.
-- @args newtargets If set, add the new hostnames to the scanning queue.
-- This the names presumably resolve to the same IP address as the
-- original target, this is only useful for services such as HTTP that
-- can change their behavior based on hostname.
--
-- @usage
-- nmap --script hostmap-ip2hosts --script-args 'hostmap-ip2hosts.prefix=hostmap-' <targets>
--
-- @output
-- Host script results:
-- | hostmap-ip2hosts: 
-- |   ip: 74.207.254.18
-- |   hosts: 
-- | http://insecure.org
-- | http://nmap.org
-- | http://sectools.org
-- | http://seclists.org
-- | https://secwiki.org
-- | http://cgi.insecure.org
-- |_  output: Saved to hostmap-insecure.org
---

author = {'Ange Gutek', 'Paulino Calderon'}

license = "Same as Nmap--See http://nmap.org/book/man-legal.html"

categories = {"external", "discovery"}

local dns = require "dns"
local ipOps = require "ipOps"
local http = require "http"
local stdnse = require "stdnse"
local target = require "target"

local HOSTMAP_BING_SERVER = "www.ip2hosts.com"
local HOSTMAP_DEFAULT_PROVIDER = "ALL"

local filename_escape, write_file

hostrule = function(host)
  return not ipOps.isPrivate(host.ip)
end

local function query_bing(ip) 
  local query = "/csv.php?ip=" .. ip
  local response
  local entries
  response = http.get(HOSTMAP_BING_SERVER, 80, query)
  local hostnames = {}
  if not response.status then
    return string.format("Error: could not GET http://%s%s", HOSTMAP_BING_SERVER, query)
  end
  entries = stdnse.strsplit(",", response.body);
  for _, entry in pairs(entries) do
    if not hostnames[entry] and entry ~= "" then
      if target.ALLOW_NEW_TARGETS then
        local status, err = target.add(entry)
      end
      hostnames[#hostnames + 1] = entry
    end
  end

  if #hostnames == 0 then
    if not string.find(response.body, "no results") then
      return "Error: found no hostnames but not the marker for \"no hostnames found\" (pattern error?)"
    end
  end
  return hostnames
end

action = function(host)
  local filename_prefix = stdnse.get_script_args("hostmap.prefix")
  local hostnames = {}
  local hostnames_str, output_str 
  local output_tab = stdnse.output_table()
  stdnse.print_debug(1, "Using database: %s", HOSTMAP_BING_SERVER)
  output_tab.ip = host.ip
  hostnames = query_bing(host.ip)

  if type(hostnames) == "string" then
    return hostnames
  end
  hostnames_str = stdnse.strjoin("\n", hostnames)
  output_tab.hosts = "\n"..hostnames_str
  --write to file
  if filename_prefix then
    local filename = filename_prefix .. filename_escape(host.targetname or host.ip)
    local status, err = write_file(filename, hostnames_str .. "\n")
    if status then
      output_tab.output = string.format("Saved to %s\n", filename)
    else
      output_tab.output = string.format("Error saving to %s: %s\n", filename, err)
    end
  end

  return output_tab
end

-- Escape some potentially unsafe characters in a string meant to be a filename.
function filename_escape(s)
  return string.gsub(s, "[%z/=]", function(c)
    return string.format("=%02X", string.byte(c))
  end)
end

function write_file(filename, contents)
  local f, err = io.open(filename, "w")
  if not f then
    return f, err
  end
  f:write(contents)
  f:close()
  return true
end