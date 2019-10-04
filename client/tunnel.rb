require "socket"
require "./utils/consts"

module Client
  class Tunnel
    attr_accessor :socket, :mutex, :busy, :last_pinged, :local_host_client

    CONNECTION_DEADL_IN_SEC = 20

    def initialize(socket, local_host_client)
      @socket = socket
      @local_host_client = local_host_client
      @mutex = Mutex.new
      @busy = false
    end

    def fileno
      @socket.fileno
    end

    def puts(data)
      @socket.puts(data)
    end

    def close
      @socket.close
    end

    def closed?
      @socket.closed?
    end

    def ping_timestamp
      @last_pinged = Time.now
    end

    def heartbeat(&func)
      return if closed?
      Utils.log.debug("tunnel_no:%d start ping process" % fileno)
      @mutex.synchronize do
        begin
          if @last_pinged.nil? || @last_pinged + CONNECTION_DEADL_IN_SEC > Time.now
            Utils.log.debug("tunnel_no:%d ping request" % fileno)
            puts(Utils::Consts::PING)
            return
          end
        rescue StandardError => e
          Utils.log.error(e)
        end

        func.call
      end
    end

    def proxy (input)
      datas = []
      begin
        Utils.log.debug("tunnel_no:%d start tunnel proxy" % fileno)
        Utils.log.debug("tunnel_no:%d " % fileno + input)
        Utils.log.debug("tunnel_no:%d " % fileno + @local_host_client.inspect)
        @local_host_client.write(input)

        # I do not know why IO.select makes this code slower
        while buffer = @local_host_client.gets
          p buffer
          if buffer.nil?
            break
          end
          datas << buffer
        end
        Utils.log.debug("tunnel_no:%d get data in tunnel proxy" % fileno)
      rescue StandardError => e
        Utils.log.error(e)
        @local_host_client.close
      end
      data = datas.join
      Utils.log.debug("tunnel_no:%d " % fileno + data)
      puts(data)
    end

    def proxy_dispatch(&func)
      Utils.log.debug("tunnel_no:%d start proxy dispatch" % fileno)
      begin
        @busy = true
        @mutex.synchronize do
          return if closed?

          datas = []
          while IO.select([@socket], nil, nil, 1)
            datas << @socket.gets
          end
          next if datas.empty?
          data = datas.join
          Utils.log.debug("tunnel_no:%d " % fileno + data)

          if data.chomp == Utils::Consts::PONG
            ping_timestamp
            Utils.log.debug("tunnel_no:%d accept pong" % fileno)
          else
            if data.start_with?(Utils::Consts::PONG)
              ping_timestamp
              data.slice!(0, Utils::Consts::PONG.length+1)
            elsif data.end_with?(Utils::Consts::PONG + "\n")
              ping_timestamp
              data.slice!(data.size - Utils::Consts::PONG.length+1, Utils::Consts::PONG.length+1)
            end

            Utils.log.debug("tunnel_no:%d reformatted data" % fileno)
            Utils.log.debug("tunnel_no:%d " % fileno + data)

            func.call(data)
          end
        end
      ensure
        @busy = false
      end
    end
  end
end


