require 'fluent/output'
require 'fluent/config/error'
require 'net/http'
require 'date'

module Fluent
    class ClickhouseOutput < BufferedOutput
        Fluent::Plugin.register_output("clickhouse", self)

        DEFAULT_TIMEKEY = 10

        config_param :host, :string
        config_param :port, :integer, default: 8123
        config_param :database, :string, default: "default"
        config_param :table, :string
	    # config_param :timezone, :string, default: ''
	    # TODO auth and SSL params. and maybe gzip
	    config_param :fields, :array, value_type: :string
        config_section :format do
            config_set_default :@type, "out_file"
        end
        config_section :buffer do
            config_set_default :@type, "file"
            config_set_default :chunk_keys, ["time"]
            config_set_default :flush_at_shutdown, true
            config_set_default :timekey, DEFAULT_TIMEKEY
        end

        def configure(conf)
        	super
	        @host = conf["host"]
		    @port = conf["port"]
        	@uri_str = "http://#{ conf['host'] }:#{ conf['port']}/"
        	@table = conf["table"]
		    @fields = fields.select{|f| !f.empty? }
        	uri = URI(@uri_str)
		    begin
        		res = Net::HTTP.get_response(uri)
			rescue Errno::ECONNREFUSED
		    	raise Fluent::ConfigError, "Couldn't connect to ClickHouse at #{ @uri_str } - connection refused" 
		end
		if res.code != "200"
        	    raise Fluent::ConfigError, "ClickHouse server responded non-200 code!!1"
        	end
        end

        def format(tag, timestamp, record)
		    datetime = Time.at(timestamp).to_datetime
		    row = Array.new
		    @fields.map { |key|
		    	if key == "tag" 
		    		row << tag
		    	elsif key == "_DATETIME"
		    		row << datetime.strftime("%s")          # To UNIX timestamp
		    	elsif key == "_DATE"
		    		row << datetime.strftime("%Y-%m-%d")	# ClickHouse 1.1.54292 has a bug in parsing UNIX timestamp into Date. 
		    	else
		    	       	row << record[key]
		    	end
		    }
		    "#{row.join("\t")}\n"
    	end

        def write(chunk)
		    http = Net::HTTP.new(@host, @port.to_i)
		    uri = URI.encode("#{ @uri_str }?query=INSERT INTO #{ @table } FORMAT TabSeparated")
		    req = Net::HTTP::Post.new(URI.parse(uri))
            req.body = chunk.read
            resp = http.request(req)
		    if resp.code != "200"
		    	log.warn "Clickhouse responded: #{resp.body}"
		    end
        end
    end
end