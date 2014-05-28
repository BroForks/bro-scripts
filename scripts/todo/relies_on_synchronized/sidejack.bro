##! sidejack.bro
##! 
##! This script detects the reuse of session cookies in different contexts.
##! 
##! Sidejacking is also known as cookie hijacking and means that an
##! attacker captured a session cookie of a victim to reuse that session.
##! Off-the-shelf tools like Firesheep_ implement this attack as a Firefox
##! extension, which makes this attack accessible to the masses.
##! 
##! In its default settings, the script raises a SessionCookieReuse notice when
##! the same session cookie is seen from different user agents. If in addition the
##! IP addresses do not match, a Sidejack notice is being triggered.
##! 
##! There exist various options to tweak the behavior of the script. First, the
##! notion of a user can be changed. In flat IP address space, it makes sense to
##! identify a user by its IP address, but this would fail in a NAT environment
##! where a single IP accommodates several users. For NAT scenarios, one could
##! define a user as a pair of IP address and USER-AGENT header. For large NATs or
##! NATs with identically configured machines, this latter notion of user could be
##! prone to false positives. The user can change the definition of a user via
##! 
##! 
##!     redef HTTP::user_is_ip = F;
##! 
##! Another issue poses the presence of absence of link-layer context. Consider a
##! hotspot or coffeeshop network operator with a private IP space. If Bro can see
##! DHCP or ARP traffic, we can crisply identify a user by its MAC address and do
##! not have to resort to high-level notions, such as provided by HTTP headers. In
##! a static setup, however, this context will likely not be available. At the same
##! time, if a different address reuses a session cookie in a static IP topology,
##! we probably observed a sidejacking attack. Furthermore, if the same address
##! uses the same session cookie from a different user agent, we report such
##! activity.  By setting
##! 
##!     redef HTTP::use_aliasing = T;
##! 
##! one tells Bro to use keep track of multiple IP addresses for the same host via
##! roam.bro. It makes only sense to set this flag when Bro actually sees DHCP
##! or ARP traffic.
##! 
##! There is another subtlety: the cookie header consists of a list of key-value
##! pairs, yet only a subset of those represent a user session while the others
##! could be random. Simply comparing the entire cookie string against a value seen
##! in the past would thus be prone to false negatives. Hence we have to restrict
##! ourselves to the relevant session-identifying subset. In fact, this is how
##! Firesheep works: it ships with site-specific handlers that define the cookie
##! keys to extract and then sets only those to impersonate a user. This motivates
##! the following design: if a specification for a particular service is available,
##! restrict the cookie to the relevant fields, and otherwise use the cookie as a
##! whole. The default set of known services that ships with the detector is based
##! on all handlers Firesheep currently implements. To extend the detection to all
##! cookies, one can set
##! 
##!     redef HTTP::known_services_only = F;
##! 
##! Finally, the timeout for cookie expiration can be adjusted, e.g.,
##! 
##!     redef HTTP::cookie_expiration = 1 day;
##! 
##! If a cookie is not seen after the cookie_expiration, the associated state
##! is removed. More information about the script can be found at
##! SidejackingBlogPost.
##! 
##! References: 
##!    
##!    SidejackingBlogPost: http://matthias.vallentin.net/blog/2010/10/taming-the-sheep-detecting-sidejacking-with-bro/
##!    Sidejacking: http://en.wikipedia.org/wiki/Session_hijacking
##!    Firesheep: http://codebutler.com/firesheep
##! 
##! Author: Matthias Vallentin
##! 
##! Contributors: Jordi Ros-Giralt (Reservoir Labs)


module HTTP;

export {
	redef enum Notice::Type += {
		## Cookie reuse by a different user agent
		SessionCookieReuse,
		## Cookie reuse by a roaming user.
		SessionCookieRoamed,
		## Cookie reuse by an attacker.
		Sidejacking
	};

	## Control how to define a user. If the flag is set, a user is defined
	## solely by its IP address and otherwise defined by the (IP, user agent)
	## pair. It can make sense to deactive this flag in a deployment upstream 
	## of a NAT. However, false positivies can then arise when the same user
	## sends the same session cookie from multiple user agents.
	const user_is_ip = T &redef;

	## Whether to keep track of multiple IP addresses for the same host. This
	## can reduce false positives for roaming clients that leave and join the
	## network under a new IP address, yet use the same session within the
	## cookie expiration interval. It makes only sense to set this flag when
	## actually sees DHCP or ARP traffic.
	const use_aliasing = F &redef;

	## Whether to restrict the analysis only to the known services listed
	## below.
	const known_services_only = T &redef;

	## Time after which a seen cookie is forgotten.
	const cookie_expiration = 1 hr &redef;

	## Describes the cookie information of a web service, such as Twitter.
	type ServiceInfo: record
	{
		desc: string;			# Service description.
		url: pattern;			# URL pattern matched against Host header.
		keys: set[string] &optional; 	# Cookie keys that define the user session.
		pat: pattern &optional;	     	# Cookie keys pattern, instead of a set.
	};

	# We track the cookie inside the HTTP state of the connection.
	redef record Info += {
		cookie: string &optional;
	};

	## Known session cookie definitions (from Firesheep handlers).
	const services: vector of ServiceInfo = {
		[$desc="AKF Demo", $url=/verify.akfdemo.com/, $keys=set("session")],
		[$desc="Amazon", $url=/amazon.com/, $keys=set("x-main")],
		[$desc="Basecamp", $url=/basecamphq.com/, $keys=set("_basecamp_session", "session_token")],
		[$desc="bit.ly", $url=/bit.ly/, $keys=set("user")],
		[$desc="Cisco", $url=/cisco.com/, $keys=set("SMIDENTITY")],
		[$desc="CNET", $url=/cnet.com/, $keys=set("urs_sessionId")],
		[$desc="Enom", $url=/enom.com/, $keys=set("OatmealCookie", "EmailAddress")],
		[$desc="Evernote", $url=/evernote.com/, $keys=set("auth")],
		[$desc="Facebook", $url=/facebook.com/, $keys=set("datr", "c_user", "lu", "sct")],
		[$desc="Fiverr", $url=/fiverr.com/, $keys=set("_fiverr_session")],
		[$desc="Flickr", $url=/flickr.com/, $keys=set("cookie_session")],
		[$desc="Foursquare", $url=/foursquare.com/, $keys=set("ext_id", "XSESSIONID")],
		[$desc="Google", $url=/google.com/, $keys=set("NID", "SID", "HSID", "PREF")],
		[$desc="Gowalla", $url=/gowalla.com/, $keys=set("__utma")],
		[$desc="Hacker News", $url=/news.ycombinator.com/, $keys=set("user")],
		[$desc="Harvest", $url=/harvestapp.com/, $keys=set("_harvest_sess")],
		[$desc="LinkedIn", $url=/linkedin.com/, $keys=set("bcookie")],
		[$desc="NY Times", $url=/nytimes.com/, $keys=set("NYT-s", "nyt-d")],
		[$desc="Pivotal Tracker", $url=/pivotaltracker.com\/dashboard/, $keys=set("tracker_session")],
		[$desc="Posterous", $url=/.*/, $keys=set("_sharebymail_session_id")],
		[$desc="Reddit", $url=/reddit.com/, $keys=set("reddit_session")],
		[$desc="ShutterStock", $url=/shutterstock.com/, $keys=set("ssssidd")],
		[$desc="StackOverflow", $url=/stackoverflow.com/, $keys=set("usr", "gauthed")],
		[$desc="tumblr", $url=/tumblr.com/, $keys=set("pfp")], 
		[$desc="Twitter", $url=/twitter.com/, $keys=set("_twitter_sess", "auth_token")],
		[$desc="Vimeo", $url=/vimeo.com/, $keys=set("vimeo")],
		[$desc="Yahoo", $url=/yahoo.com/, $keys=set("T", "Y")],
		[$desc="Yelp", $url=/yelp.com/, $keys=set("__utma")],
		[$desc="Windows Live", $url=/live.com/, $keys=set("MSPProf", "MSPAuth", "RPSTAuth", "NAP")],
		[$desc="Wordpress", $url=/wordpress.com/, $pat=/wordpress_[0-9a-fA-F]+/]
	} &redef;
}

@ifdef(use_aliasing)
@load roam
@endif

## Per-cookie state.
type CookieContext: record
{
	mac: string;		## MAC address of the user.
	client: addr;		## IP address of the user.
	user_agent: string;	## User-Agent header.
	last_seen: time;	## Last time we saw the cookie from this user.
	conn: string;		## Last seen connection this cookie appeared in.
	cookie: string;		## The session cookie, as seen the last time.
	service: string;	## The web service description of this cookie.
};

# Map cookies to their contextual state.
global cookies: table[string] of CookieContext &read_expire = cookie_expiration;

# Create a unique user session identifier based on the relevant cookie keys.
# Return the empty string if the sessionization does not succeed.
function sessionize(cookie: string, info: ServiceInfo) : string
{
	local id = "";
	local fields = split(cookie, /; /);

	if (info?$keys)
	{
		local matches: table[string] of string;
		for (i in fields)
		{
			local s = split1(fields[i], /=/);
			if (s[1] in info$keys)
				matches[s[1]] = s[2];
		}

		if (|matches| == |info$keys|)
			for (key in info$keys)
			{
				if (id != "")
					id += "; ";
				id += key + "=" + matches[key];
			}
	}

	if (info?$pat)
	{
		for (i in fields)
		{
			s = split1(fields[i], /=/);
			if (s[1] == info$pat)
				id += id == "" ? fields[i] : cat("; ", fields[i]);
		}
	}

	return id;
}

function is_aliased(client: addr, ctx: CookieContext) : bool
{
	if (client in Roam::ip_to_mac)
	{
		local mac = Roam::ip_to_mac[client];
		if (mac == ctx$mac && mac in Roam::mac_to_ip
			&& client in Roam::mac_to_ip[mac])
			return T;
	}

	return F;
}

function update_cookie_context(ctx: CookieContext, c: connection)
{
	ctx$last_seen = network_time();
	ctx$conn = c$uid;
	if (use_aliasing && ctx$client in Roam::ip_to_mac)
		ctx$mac = Roam::ip_to_mac[ctx$client];
}

function format_address(a: addr) : string
{
	if (use_aliasing && a in Roam::ip_to_mac)
		return fmt("%s[%s]", a, Roam::ip_to_mac[a]);
	else
		return fmt("%s", a);
}

function report_session_reuse(c: connection, ctx: CookieContext)
{
	local attacker = format_address(c$id$orig_h);
	local victim = format_address(ctx$client);
	NOTICE([$note=SessionCookieReuse, $conn=c,
			$suppress_for=10min,
			$user=fmt("%s '%s'", attacker, c$http$user_agent),
			$msg=fmt("%s reused %s session %s via cookie %s",
				attacker, ctx$service, ctx$conn, ctx$cookie),
			$identifier=cat(ctx$cookie, c$http$user_agent)
		   ]);
}

function report_session_roamed(c: connection, ctx: CookieContext)
{
	local roamer = format_address(c$id$orig_h);
	NOTICE([$note=SessionCookieRoamed, $conn=c,
			$suppress_for=10min,
			$user=fmt("%s '%s'", roamer, c$http$user_agent),
			$msg=fmt("%s roamed %s session %s via cookie %s",
				roamer, ctx$service, ctx$conn, ctx$cookie),
			$identifier=cat(ctx$cookie, roamer)]);
}

# Create a unique user ID based on the notion of user.
function make_client(c: connection) : string
{
	return user_is_ip ? fmt("%s", c$id$orig_h) : 
			fmt("%s '%s'", c$id$orig_h, c$http$user_agent);
}

function report_sidejacking(c: connection, ctx: CookieContext)
{
	local attacker = format_address(c$id$orig_h);
	NOTICE([$note=Sidejacking, $conn=c,
			$suppress_for=10min,
			$user=fmt("%s '%s'", attacker, c$http$user_agent),
			$msg=fmt("%s hijacked %s session %s via cookie %s",
				attacker, ctx$service, ctx$conn, ctx$cookie),
			$identifier=cat(ctx$cookie, make_client(c))]);
}

# Track the cookie value inside HTTP.
event http_header(c: connection, is_orig: bool, name: string, value: string)
{
	if (is_orig && name == "COOKIE")
		c$http$cookie = value;
}

# We use this event as an indicator that all headers have been seen. That is,
# this event guarantees that the HTTP state inside the connection record
# has all fields populated.
event http_all_headers(c: connection, is_orig: bool, hlist: mime_header_list)
{
	if (! is_orig)
		return;

	if (! c$http?$cookie || c$http$cookie == "" )
		return;

	local cookie = "";
	local service = c$http$host;
	if (service != "")
		for (s in services)
		{
			local info = services[s];
			if (info$url in service)
			{
				cookie = sessionize(c$http$cookie, info);
				if (cookie != "")
				{
					service = info$desc;
					break;
				}
			}
		}

	if (cookie == "")
	{
		if (known_services_only)
			return;

		cookie = c$http$cookie;
	}
	else
		cookie = fmt("subset %s", cookie);

	local client = c$id$orig_h;
	local user = make_client(c);

	if (cookie !in cookies)
	{
		local mac = "";
		if (use_aliasing && client in Roam::ip_to_mac)
			mac = Roam::ip_to_mac[client];

		cookies[cookie] =
		[
			$mac=mac,
			$client=client,
			$user_agent=c$http$user_agent,
			$last_seen=network_time(),
			$conn=c$uid,
			$cookie=cookie,
			$service=service
		];

		return;
	}

	local ctx = cookies[cookie];
	if (cookie != ctx$cookie)
		return;

	if (user_is_ip)
	{
		if (client == ctx$client)
		{
			if (c$http$user_agent != ctx$user_agent)
			{
				report_session_reuse(c, ctx);

				# Uncommenting this will have the effect of reversing the
				# current and previous user agent, resulting in another notice
				# when the previous user agent appears again.
				#ctx$user_agent = c$http$user_agent;
			}

			update_cookie_context(ctx, c);
		}
		else if (c$http$user_agent != ctx$user_agent)
		{
			report_sidejacking(c, ctx);
		}
		else if (use_aliasing)
		{
			if (is_aliased(client, ctx))
			{
				update_cookie_context(ctx, c);
				report_session_roamed(c, ctx);
			}
			else
				report_sidejacking(c, ctx);
		}
	}
	else if (client == ctx$client && c$http$user_agent == ctx$user_agent)
		update_cookie_context(ctx, c);
	else
		report_sidejacking(c, ctx);
}