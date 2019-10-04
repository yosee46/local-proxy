require "socket"

module Server
  class Tunnel
    attr_accessor :socket, :mutex, :tunnel_hash_index, :proxy_dest_socket

    CONNECTION_DEADL_IN_SEC = 20

    def initialize(socket, data)
      array = data.chomp!.split('+')
      tunnel_hash_index = array[1]
      old_fileno = array[2]

      unless old_fileno.nil?
        old_tunnel = @tunnels[old_fileno]
        old_tunnel.close unless old_tunnel.nil?
      end

      @socket = socket
      @tunnel_hash_index = tunnel_hash_index
      @mutex = Mutex.new

      Utils.log.debug("tunnel_no:%d new tunnel process" % fileno)
      puts("new_tunnel")
    end

    def fileno
      @socket.fileno
    end

    def puts(data)
      @socket.puts(data)
    end

    def close
      @mutex.synchronize do
        begin
          Utils.log.debug("tunnel_no:%d old tunnel close" % fileno)
          old_tunnel.close
        rescue StandardError => e
          Utils.log.error(e)
        end
      end
    end

    def closed?
      @socket.closed?
    end

    def ping_pong
      @mutex.synchronize do
        datas = []
        while IO.select [@socket], nil, nil, 1
          datas << @socket.gets
        end
        next if datas.empty?
        data = datas.join
        Utils.log.debug("tunnel_no:%d accept ping" % fileno)

        if data.chomp.start_with?(Utils::Consts::PING)
          Utils.log.debug("tunnel_no:%d match ping message" % fileno)
          puts(Utils::Consts::PONG)
          Utils.log.debug("tunnel_no:%d return pong to tunnel client" % fileno)
        end
      end
    end

    def proxy (proxy_dest_socket, input)
      @mutex.synchronize do
        begin
          return false if closed?

          Utils.log.debug("tunnel_no:%d puts request data into tunnel" % fileno)
          puts(input)

          if IO.select [@socket], nil, nil, 10
            @proxy_dest_socket = proxy_dest_socket

            loop do
              datas = []
              while IO.select [@socket], nil, nil, 1
                datas << @socket.gets
              end
              next if datas.empty?
              data = datas.join

              if data.chomp.start_with?(Utils::Consts::PING)
                puts(Utils::Consts::PONG)
                Utils.log.debug("tunnel_no:%d ping process" % fileno)
                next
              end

              data = data.gsub(/\*\*ping\*\*/, "")
              @proxy_dest_socket.puts(data)
              Utils.log.debug("tunnel_no:%d proxy data to client server" % fileno)

              @proxy_dest_socket.close()
              break
            end

          else
            @proxy_dest_socket.puts(data)
            @proxy_dest_socket.close()
            Utils.log.debug("tunnel_no:%d url socket close" % fileno)
          end
        rescue StandardError => e
          Utils.log.error(e)
          return false
        end
        true
      end
    end
  end
end
