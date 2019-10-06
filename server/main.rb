require "socket"
require 'thread'
require 'optparse'
require "./server/tunnel"
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
          while readable_sockets = IO.select(@tunnels.reject { |fileno, tunnel| tunnel.closed? }.values.map { |tunnel| tunnel.socket }, nil, nil, 1)
            readable_socket = readable_sockets[0][0]
            tunnel = find_tunnel(readable_socket)
            tunnel.ping_pong unless tunnel.nil?
          end
        rescue StandardError => e
          Utils.log.error(e)
        end
      end
    end

    def find_tunnel(socket)
      @tunnels.each..reject { |fileno, tunnel| tunnel.closed? }.values.each do |tunnel|
        return tunnel if socket.fileno == tunnel.socket.fileno
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
          tunnel_hash_index = array[1]
          old_tunnel_hash_fileno = array[2]

          unless old_tunnel_hash_fileno.nil?
            old_tunnel = @tunnels[old_tunnel_hash_fileno]
            old_tunnel.close unless old_tunnel.nil?
          end

          new_tunnel = Tunnel.new(socket, tunnel_hash_index)
          @tunnels[new_tunnel.tunnel_hash_index] = new_tunnel

        elsif data.start_with?("GET ") and !data.start_with?("GET /nginx_status")
          Utils.log.debug("accept request")
          Utils.log.debug(data)
          while writable_sockets = IO.select(nil, @tunnels.reject { |fileno, tunnel| tunnel.closed? }.values.map { |tunnel| tunnel.socket }, nil, 1)
            writable_socket = writable_sockets[1][0]
            next if writable_socket.nil?

            Utils.log.debug("before tunnel syncronize to puts request data")
            tunnel = find_tunnel(writable_socket)
            break if tunnel.proxy(socket, data)
          end

        end
      rescue StandardError => e
        Utils.log.error(e)
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
