require "socket"
require 'thread'
require 'optparse'
require "./utils/logger"
require "./utils/config_loader"

module Server

  class ServerModel

    def initialize
      @tunnels = Hash.new
      @mutexes = Hash.new
      @url_sockets = Hash.new
      @fileno_hash = Hash.new
    end

    def ping_pong
      loop do
        begin
          while tunnels_data = IO.select(@tunnels.values.reject { |tunnel| tunnel.closed? }, nil, nil, 1)
            tunnel = tunnels_data[0][0]
            Utils.log.debug(@fileno_hash)
            Utils.log.debug(tunnel.fileno)
            datas = []
            while IO.select [tunnel], nil, nil, 1
              datas << tunnel.gets
            end
            next if datas.empty?
            data = datas.join
            Utils.log.debug("accept ping")

            if data.chomp.start_with?("**ping**")
              Utils.log.debug("accept ping")
              tunnel.puts("**pong**")
              Utils.log.debug("retun pong")
            end
          end
        rescue StandardError => e
          Utils.log.error(e.message)
        end
      end
    end

    def accept(socket)
      begin
        datas = []
        while IO.select [socket], nil, nil, 1
          datas << socket.gets
        end
        data = datas.join

        if data.start_with?("tunnel")
          Utils.log.debug("accept tunnel")
          array = data.chomp!.split('+')
          fileno = array[1]
          old_fileno = array[2]

          unless old_fileno.nil?
            @mutexes[old_fileno].synchronize do
              begin
                Utils.log.debug("old tunnel process")
                Utils.log.debug(@tunnels.inspect)
                old_tunnel = @tunnels[old_fileno]
                unless old_tunnel.nil?
                  old_tunnel.close
                end
              rescue StandardError => e
                Utils.log.error(e.message)
              end
            end
          end

          Utils.log.debug("new tunnel process")
          Utils.log.debug(@tunnels.inspect)
          socket.puts("new_tunnel")
          @tunnels[fileno] = socket
          @fileno_hash[socket.fileno] = fileno
          @mutexes[fileno] = Mutex.new


        elsif data.start_with?("GET ") and !data.start_with?("GET /nginx_status")

          Utils.log.debug("accept request")
          Utils.log.debug(data)
          while writable_tunnel = IO.select(nil, @tunnels.values.reject { |tunnel| tunnel.closed? }, nil, 1)
            tunnel = writable_tunnel[1][0]
            Utils.log.debug("setting tunnel process")
            Utils.log.debug(tunnel.inspect)

            next if tunnel.nil?
            Utils.log.debug("start tunnel process")
            fileno = @fileno_hash[tunnel.fileno]
            @mutexes[fileno].synchronize do
              begin
                next if tunnel.closed?
                Utils.log.debug("putting tunnel process")
                tunnel.puts(data)
                if IO.select [tunnel], nil, nil, 10
                  Utils.log.debug("socket")
                  Utils.log.debug(socket.inspect)
                  @url_sockets[fileno] = socket

                  loop do
                    datas = []
                    while IO.select [tunnel], nil, nil, 1
                      datas << tunnel.gets
                    end
                    next if datas.empty?
                    data = datas.join

                    if data.chomp.start_with?("**ping**")
                      tunnel.puts("**pong**")
                      Utils.log.debug("ping process")
                      next
                    end

                    data = data.gsub(/\*\*ping\*\*/, "")
                    socket.puts(data)
                    Utils.log.debug("proxy data to client server")

                    socket.close()
                    break
                  end

                else
                  socket.puts(data)
                  socket.close()
                  Utils.log.debug("url socket close")
                end
              rescue StandardError => e
                Utils.log.error(e.message)
                next
              end
            end
            break
          end
        end
      rescue StandardError => e
        Utils.log.error(e.message)
      end

    end
  end

  class Main
    def main
      load_config
      server = TCPServer.open(@port)
      server_model = ServerModel.new

      Thread.start { server_model.ping_pong }
      loop do
        Thread.start(server.accept) do |socket|
          server_model.accept(socket)
        end
      end

      server.close
    end

    def load_config
      @port = Utils.config_loader.config['port']
    end
  end
end

opt = OptionParser.new
config_file_path = nil
opt.on('-c', '--config_path STRING') {|v| config_file_path = v }
opt.parse(ARGV)

Utils.config_loader = Utils::ConfigLoader.new(Utils::ENV::SERVER, config_file_path)

Utils.log = Utils::Logger.new
Utils.log.debug(Utils.config_loader.config)

Server::Main.new.main
