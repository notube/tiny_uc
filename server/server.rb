# half-done and crufty UC server implementation
# it uses XMPP to talk to the 'tv' (a web page) - better would be websockets probably
# it uses some online services for a live tv and on demand content

require 'webrick'
require 'rubygems'
require 'dnssd'
require 'uri'
require 'open-uri'
require 'net/http'
require 'json/pure'
require 'time'
require 'xmpp4r'
require 'xmpp4r/roster'
require 'xmpp4r/client'
require 'xmpp4r/muc'
require 'pp'

module F

  include Jabber

  $changed = false
  $count = 1
  $muc = nil
  $oldtext = ""
  $oldchans = ""
  

  #   server.mount( '/uc/', UCServlet )
  
  class UCServlet < WEBrick::HTTPServlet::AbstractServlet
    def do_OPTIONS(req, res)
       F.options(req,res)
    end

    def do_GET(req, resp)   
      resp.body = File.read("sample_xml/uc.xml") # this is just the example from the spec
      resp['content-type'] = 'text/plain'
      resp["Access-Control-Allow-Origin"]="*"
      resp["Access-Control-Allow-Methods"] = "GET, POST"
      resp["Access-Control-Allow-Headers"]="X-Requested-With, Origin"
      resp["Access-Control-Max-Age"]="86400"
      raise WEBrick::HTTPStatus::OK
    end
  end


  #   server.mount( '/uc/source-lists/uc_default', ChannelsServlet )
  #   server.mount( '/uc/sources', ChannelsServlet )
  #   list of channels with what's on now

  class ChannelsServlet < WEBrick::HTTPServlet::AbstractServlet
    def do_OPTIONS(req, res)
       F.options(req,res)
    end

    def do_GET(req, resp)   
      # get the list of programmes on now from notube service
      # path is the programmes url
      path = req.path
      path.gsub!( /.*\//,"")

      chans = ["bbcone","bbctwo","bbcthree","bbcfour","bbcnews"]
      chan_paths = {"BBCOne"=>"bbcone","BBCTwo"=>"bbctwo","BBCThree"=>"bbcthree","BBCFour"=>"bbcfour","BBCNews"=>"bbcnews"}
      chan_names = {"bbcone"=>"BBC ONE","bbctwo"=>"BBC TWO","bbcthree"=>"BBC THREE","bbcfour"=>"BBC FOUR","bbcnews"=>"BBC NEWS"}
      chan_sid = {"bbcone"=>"1001","bbctwo"=>"1002","bbcthree"=>"1007","bbcfour"=>"1009","bbcnews"=>"1080"}
      chan_lcn={"bbcone"=>"001","bbctwo"=>"002","bbcthree"=>"007","bbcfour"=>"009","bbcnews"=>"080"}

      u = "http://dev.notu.be/2011/04/on_now/epg?channel=#{chans.join(',')}&fmt=js"
      if(path && chan_paths[path])
        u = "http://dev.notu.be/2011/04/on_now/epg?channel=#{chan_paths[path]}&fmt=js"
      end

      r = F.get_data(u)
      j = JSON.parse(r.to_s)
      ordered = {}

      j.each do |prog|
        pid = prog["pid"]
        service = prog["service"]
        text = "
<source sid=\"#{chan_sid[service]}\" name=\"#{chan_names[service]}\" sref=\"http://www.bbc.co.uk/services/#{service}#service\" default-content-id=\"http://www.bbc.co.uk/programmes/#{pid}\" live=\"true\" linear=\"true\" follow-on=\"true\" lcn=\"#{chan_lcn[service]}\"/>
"
        ordered[service]= text
      end

      text = "<response resource=\"uc/source-lists/uc_default\">
  <sources>
"
      chans.each do |c|
           text = "#{text} #{ordered[c]}"
      end

# on demand example
      text = "#{text} 
        <source name=\"iPlayer Random\"
        sid=\"iPlayer\"
        live=\"false\"
        linear=\"false\"
        follow-on=\"false\"
        sref=\"http://nscreen.notu.be/iplayer_dev/api/random?fmt=js\"
        owner=\"BBC iPlayer\"/>
  </sources>
</response>
"

      # for the /events stuff - we make a note when things have changed

      if($oldtext!=text)
        $changed = true
        $oldtext = text
        $count = $count+1
      else
        $changed = false
      end

      resp.body = text
      resp["Access-Control-Allow-Origin"]="*"
      resp["Access-Control-Allow-Methods"] = "GET, POST"
      resp["Access-Control-Allow-Headers"]="X-Requested-With, Origin"
      resp["Access-Control-Max-Age"]="86400"
      resp['content-type'] = 'text/xml'
      raise WEBrick::HTTPStatus::OK
    end
  end


  #   server.mount( '/uc/search/source-lists/uc_default', ChannelsDataServlet )

  class ChannelsDataServlet < WEBrick::HTTPServlet::AbstractServlet

    def do_OPTIONS(req, res)
       F.options(req,res)
    end

    def do_GET(req, resp)   
      chans = ["bbcone","bbctwo","bbcthree","bbcfour","bbcnews"]
      chan_names = {"bbcone"=>"BBC ONE","bbctwo"=>"BBC TWO","bbcthree"=>"BBC THREE","bbcfour"=>"BBC FOUR","bbcnews"=>"BBC NEWS"}
      chan_sid = {"bbcone"=>"1001","bbctwo"=>"1002","bbcthree"=>"1007","bbcfour"=>"1009","bbcnews"=>"1080"}
      chan_lcn={"bbcone"=>"001","bbctwo"=>"002","bbcthree"=>"007","bbcfour"=>"009","bbcnews"=>"080"}
      u = "http://dev.notu.be/2011/04/on_now/epg?channel=#{chans.join(',')}&fmt=js"
      r = F.get_data(u)
      j = JSON.parse(r.to_s)
      ordered = {}
      j.each do |prog|
        pid = prog["pid"]
        service = prog["service"]
        image = prog["image"]
        start = prog["start"]
        en = prog["end"]
        title = prog["core_title"]
        text = "
<results more=\"true\">
  <content sid=\"#{chan_sid[service]}\" cid=\"#{pid}\" global-content-id=\"#{pid}\"
title=\"#{title}\" interactive=\"false\" start=\"#{start}\" acquirable-until=\"#{start}\"
presentable-from=\"#{start}\" presentable-until=\"#{en}\">
    <synopsis>
#{title}
    </synopsis>
  </content>
</results>
"
        ordered[service]=text
      end

      t2 = "
<results more=\"true\">
  <content sid=\"iPlayer\" title=\"Random iPlayer Content\" interactive=\"false\" global-content-id=\"random\">
    <synopsis>
      Random iPlayer Content
    </synopsis>
  </content>
</results>
"
      text = "<response resource=\"uc/search/source-lists/uc_default\">
"
      chans.each do |c|
           text = "#{text} #{ordered[c]}"
      end

      text = "#{text}
#{t2}
</response>
"

      if($oldchans!=text)
        $changed = true
        $oldchans = text
        $count = $count+1
      else
        $changed = false
      end

      resp.body = text

      resp['content-type'] = 'text/xml'
      resp["Access-Control-Allow-Origin"]="*"
      resp["Access-Control-Allow-Methods"] = "GET, POST"
      resp["Access-Control-Allow-Headers"]="X-Requested-With, Origin"
      resp["Access-Control-Max-Age"]="86400"
      raise WEBrick::HTTPStatus::OK
    end
  end


#  server.mount( '/uc/outputs', OutputsServlet )

  class OutputsServlet < WEBrick::HTTPServlet::AbstractServlet

    def do_OPTIONS(req, res)
       F.options(req,res)
    end

    def do_GET(req, resp)   
      resp.body = File.read("sample_xml/outputs.xml")
      resp['content-type'] = 'text/xml'
      resp["Access-Control-Allow-Origin"]="*"
      resp["Access-Control-Allow-Methods"] = "GET, POST"
      resp["Access-Control-Allow-Headers"]="X-Requested-With, Origin"
      resp["Access-Control-Max-Age"]="86400"
      raise WEBrick::HTTPStatus::OK
    end
  end


#  server.mount( '/uc/time', TimeServlet )


  class TimeServlet < WEBrick::HTTPServlet::AbstractServlet
    def do_OPTIONS(req, res)
       F.options(req,res)
    end

    def do_GET(req, resp)   
      t = Time.now.getutc.strftime("%Y-%m-%dT%H:%M:%SZ")
      b = "<response resource=\"uc/time\">
  <time rcvdtime=\"#{t}\"
        replytime=\"#{t}\"/>
</response>
"
      resp.body = b
      resp['content-type'] = 'text/xml'
      resp["Access-Control-Allow-Origin"]="*"
      resp["Access-Control-Allow-Methods"] = "GET, POST"
      resp["Access-Control-Allow-Headers"]="X-Requested-With, Origin"
      resp["Access-Control-Max-Age"]="86400"
      raise WEBrick::HTTPStatus::OK
    end
  end


#   server.mount( '/uc/outputs/0', OutputsMainServlet )

  class OutputsMainServlet < WEBrick::HTTPServlet::AbstractServlet
    def do_GET(req, resp)   
      #@@fix me to make it 'real'. app stuff interesting? (p41 WHP194)
      b = "<response resource=\"uc/outputs/0\">
  <output name=\"Main Screen\">
    <settings volume=\"0.5\" mute=\"false\" aspect=\"16:9\"/>
    <programme sid=\"BBCOne\" cid=\"2009-12-14T22%3a00%3a00Z\" />
    <playback speed=\"1.0\"/>
  </output>
</response>
"
      resp.body = b
      resp['content-type'] = 'text/xml'
      resp["Access-Control-Allow-Origin"]="*"
      resp["Access-Control-Allow-Methods"] = "GET, POST"
      resp["Access-Control-Allow-Headers"]="X-Requested-With, Origin"
      resp["Access-Control-Max-Age"]="86400"
      raise WEBrick::HTTPStatus::OK
    end
  end


#   server.mount( '/uc/outputs/0/settings', OutputsMainSettingsServlet )

  class OutputsMainSettingsServlet < WEBrick::HTTPServlet::AbstractServlet

    def do_OPTIONS(req, res)
       F.options(req,res)
    end
    def do_GET(req, resp)   

      #@@fix me to make it 'real' - keep track
      b = "<response resource=\"uc/outputs/0/settings\">
  <settings volume=\"0.5\" mute=\"false\" aspect=\"16:9\"/>
</response>
"
      resp.body = b
      resp['content-type'] = 'text/xml'
      resp["Access-Control-Allow-Origin"]="*"
      resp["Access-Control-Allow-Methods"] = "GET, POST"
      resp["Access-Control-Allow-Headers"]="X-Requested-With, Origin"
      resp["Access-Control-Max-Age"]="86400"
      raise WEBrick::HTTPStatus::OK
    end
  end
  

#   server.mount( '/uc/source-lists', SourceListsServlet )

  class SourceListsServlet < WEBrick::HTTPServlet::AbstractServlet
    def do_OPTIONS(req, res)
       F.options(req,res)
    end
    def do_GET(req, resp)   
      resp.body = File.read("sample_xml/source-lists.xml")
      resp['content-type'] = 'text/xml'
      raise WEBrick::HTTPStatus::OK
    end
  end


#   server.mount( '/uc/search/global-content-id/', PlayCridServlet )
#   play the programme

  class PlayCridServlet < WEBrick::HTTPServlet::AbstractServlet
    def do_OPTIONS(req, res)
       F.options(req,res)
    end

    def do_GET(req, resp)   
      resp.body = req.path
      path = req.path
      path.gsub!( /.*\//,"")

      # use resolver
      u = "http://services.notu.be/resolve?uri\[\]=http://www.bbc.co.uk/programmes/#{path}#programme"
      r = F.get_data(u)
      j = JSON.parse(r.to_s)

      results = {}
## add image and stuff
## @@ this shoudl be XML

      if(j[0] && j[0]["pid"])
        results["pid"]=j[0]["pid"]
        results["id"]=path
        results["title"]=j[0]["title"]
        results["video"]=j[0]["crid"]
        results["start"]=j[0]["start"]
        results["end"]=j[0]["end"]
        results["service"]=j[0]["service"]
      else
        if(j[1] && j[1]["pid"])
          results["pid"]=j[1]["pid"]
          results["id"]=path
          results["title"]=j[1]["title"]
          results["video"]=j[1]["crid"]
          results["service"]=j[1]["service"]
          results["start"]=j[0]["start"]
          results["end"]=j[0]["end"]
        end
      end

      on_now = false
      if(results["start"] && results["end"])
         now = Time.now
         s = Time.parse(results["start"]);
         e = Time.parse(results["end"]);
         if(s<now && now<e)
           on_now=true
         end
      end
      results["on_now"]=on_now

      if(!results["pid"])#fails sometimes :(
        u = "http://www.bbc.co.uk/programmes/#{path}.json?"
        r = F.get_data(u)
        j = JSON.parse(r.to_s)
        title = j["programme"]["display_title"]["title"]      
        # more
        results["title"]=title
        results["pid"]=path
      end

#      {"id"=>"v5k7r","pid"=>"v5k7r","video"=>"crid://www.five.tv/v5k7r","image"=>"channel_images/Channel_5.png","title"=>"******Superior 
#      Interiors With Kelly Hoppen","description"=>"Award-winning interior 
#      designer Kelly Hoppen clashes with one of her biggest fans while 
#      transforming a living room into a modern multi-functional 
#      space.","explanation"=>"","action"=>"play","shared_by"=>"kkjkj"}

      puts "MUC #{$muc}"
      $muc.say(JSON.pretty_generate(results))

      $changed = true
      $count = $count+1

#      resp.body = "<result>#{path}</result>"#@@fixme
      resp.body = JSON.pretty_generate(results)#@@fixme - should be xml
#      resp['content-type'] = 'text/xml'
      resp['content-type'] = 'text/json'

      resp["Access-Control-Allow-Origin"]="*"
      resp["Access-Control-Allow-Methods"] = "GET, POST"
      resp["Access-Control-Allow-Headers"]="X-Requested-With, Origin"
      resp["Access-Control-Max-Age"]="86400"
      raise WEBrick::HTTPStatus::OK
    end
  end



#  server.mount( '/uc/search/text/', SearchServlet )

  class SearchServlet < WEBrick::HTTPServlet::AbstractServlet
    def do_OPTIONS(req, res)
       F.options(req,res)
    end

    def do_GET(req, resp)   
      resp.body = req.path
      path = req.path
      term = path.gsub( /.*\//,"")
      u = "http://nscreen.notu.be/iplayer_dev/api/search?fmt=js&q="+term;
      r = F.get_data(u)

      resp.body = r  #@@fixme
      resp['content-type'] = 'text/javascript'
      resp["Access-Control-Allow-Origin"]="*"
      resp["Access-Control-Allow-Methods"] = "GET, POST"
      resp["Access-Control-Allow-Headers"]="X-Requested-With, Origin"
      resp["Access-Control-Max-Age"]="86400"
      raise WEBrick::HTTPStatus::OK
      raise WEBrick::HTTPStatus::OK
    end
  end


  #  server.mount( '/uc/events', EventsServlet )
  # events

  class EventsServlet < WEBrick::HTTPServlet::AbstractServlet
      def do_OPTIONS(req, res)
         F.options(req,res)
      end
      def do_GET(req, resp)   

        path = req.query
        count_since = 0
        if(path["since"])
          c = path["since"]
          count_since = c.to_i
        end


        r = "<response resource=\"uc/events\">
  <events notification-id=\"#{$count}\">
    <resource rref=\"\"/>
  </events>
</response>
"   

        if($changed && count_since<$count)
          r = "<response resource=\"uc/events\">
  <events notification-id=\"#{$count}\">
    <resource rref=\"uc/outputs/0\"/>
  </events>
</response>
"   

        end


        resp.body = r  #@@fixme
        resp['content-type'] = 'text/xml'
        resp["Access-Control-Allow-Origin"]="*"
        resp["Access-Control-Allow-Methods"] = "GET, POST"
        resp["Access-Control-Allow-Headers"]="X-Requested-With, Origin"
        resp["Access-Control-Max-Age"]="86400"
        raise WEBrick::HTTPStatus::OK
      end
  end


  # web server

  server = WEBrick::HTTPServer.new( :Port => 48875 )
  
  server.mount( '/uc/', UCServlet )
  server.mount( '/uc/time', TimeServlet )
  server.mount( '/uc/events', EventsServlet )
  server.mount( '/uc/outputs', OutputsServlet )
  server.mount( '/uc/sources', ChannelsServlet )
  server.mount( '/uc/outputs/0', OutputsMainServlet )
  server.mount( '/uc/outputs/main', OutputsMainServlet )
  server.mount( '/uc/outputs/0/settings', OutputsMainSettingsServlet )
  server.mount( '/uc/outputs/main/settings', OutputsMainSettingsServlet )
  server.mount( '/uc/source-lists', SourceListsServlet )
  server.mount( '/uc/source-lists/uc_default', ChannelsServlet )
  server.mount( '/uc/search/source-lists/uc_default', ChannelsDataServlet )
  server.mount( '/uc/search/global-content-id/', PlayCridServlet )
  server.mount( '/uc/search/text/', SearchServlet )
  server.mount( '/uc/search/outputs/0', ChannelsServlet )

  # zerconf / dnssec stuff
  
  handle = DNSSD.register('uc', '_universalctrl._tcp', 'local', 48875, nil)

  ['INT', 'TERM'].each { |signal| 
    trap(signal) { server.shutdown; handle.stop; }
  }

  @@dataz = {}

  @@client= nil
  @@zid="telly" #needs to be a registered user

  # various module methods

  # CORS stuff

  def self.options(req,res)
# Specify domains from which requests are allowed
        res["Access-Control-Allow-Origin"]="*"

# Specify which request methods are allowed
        res["Access-Control-Allow-Methods"] = "GET, POST"

# Additional headers which may be sent along with the CORS request
# The X-Requested-With header allows jQuery requests to go through
        res["Access-Control-Allow-Headers"]="X-Requested-With, Origin"

# Set the age to 1 day to improve speed/caching.
        res["Access-Control-Max-Age"]="86400"
        res.body=""
        res.status = 200
  end


  # get a url
  def self.get_data(z)
        useragent = "NotubeAgent/0.6"
        u =  URI.parse z
        req = Net::HTTP::Get.new(u.request_uri,{'User-Agent' => useragent})
        req = Net::HTTP::Get.new( u.path+ '?' + u.query )
        begin
          res2 = Net::HTTP.new(u.host, u.port).start {|http|http.request(req) }
        end
        r = ""
        begin
          r = res2.body
        rescue OpenURI::HTTPError=>e
          puts e
          case e.to_s
            when /^404/
               raise 'Not Found'
            when /^304/
               raise 'No Info'
          end
        end
        return r
  end


  # XMPP stuff

  def self.connect
       @@client.connect
       @accept_subscriptions = true
       password = "sekret"
       @@client.auth(password)
       @@client.send(Presence.new.set_type(:available))
       puts "about to create MUC"
       $muc = MUC::SimpleMUCClient.new(@@client)
       self.start_join_callback
       room_name = "default_muc"# may want to change room name
       server = "jabber.example.com"
       $muc.join(Jabber::JID.new("#{room_name}@conference.#{server}/#{@@zid}"))
       $muc.say("{\"name\":\"#{@@zid}\",\"obj_type\":\"tv\",\"id\":\"#{@@zid}\",\"nowp\":null,\"suggestions\":[],\"shared\":[],\"history\":[]}")

  end

  def self.start_join_callback
       $muc.add_join_callback { |time,nick,text|
         puts "{\"name\":\"#{@@zid}\",\"obj_type\":\"tv\",\"id\":\"#{@@zid}\",\"nowp\":null,\"suggestions\":[],\"shared\":[],\"history\":[]}"
         $muc.say("{\"name\":\"#{@@zid}\",\"obj_type\":\"tv\",\"id\":\"#{@@zid}\",\"nowp\":null,\"suggestions\":[],\"shared\":[],\"history\":[]}")
       }
  end


  def self.dostuff
        server = "jabber.example.com"
        jid = "#{@@zid}@#{server}" #@@fixme for your server
        @@client = Client.new(jid)
        Jabber::debug = false
        self.connect
  end

  self.dostuff
  
  server.start

end
