require "socket"
require "yaml"
require 'optparse'
require "./client/tunnel"
require "./utils/logger"
require "./utils/config_loader"

module Client
  class Main
    def main
      client_model = ClientModel.new

      threads = []
      threads << Thread.start do
        client_model.heartbeat
      end
      threads << Thread.start do
        begin
          client_model.control
        rescue StandardError => e
          Utils.log.error(e.message)
          Utils.log.error(e.backtrace)
          client_model.control
        end
      end
      threads.each { |thr| thr.join }

    end
  end

  class ClientModel
    attr_accessor :tunnels

    def initialize
      load_config
      @tunnels = Hash.new
      @tunnel_thread_num.times do
        socket = TCPSocket.open(@remote_host, @remote_port)
        socket.puts("tunnel+#{socket.fileno}")
        if IO.select([socket], nil, nil, 2)
          if socket.gets.chomp! == "new_tunnel"
            Utils.log.debug("establish new tunnel")
            local_host_client = TCPSocket.open(@local_host, @local_port)
            @tunnels[socket.fileno] = ::Client::Tunnel.new(socket, local_host_client)
          end
        end
      end
    end

    def load_config
      @remote_host = Utils.config_loader.config['remote_host']
      @remote_port = Utils.config_loader.config['remote_port']
      @local_host = Utils.config_loader.config['local_host']
      @local_port = Utils.config_loader.config['local_port']
      @tunnel_thread_num = Utils.config_loader.config['tunnel_thread_num']
    end

    def heartbeat_tunnel
      copy = @tunnels.dup
      copy.each do |fileno, tunnel|
        tunnel.heartbeat do
          begin
            new_socket = TCPSocket.open(@remote_host, @remote_port)
            new_socket.puts("tunnel+#{new_socket.fileno}+#{fileno}")
            if IO.select([new_socket], nil, nil, 5)
              Utils.log.debug("establis new tunnel")
              next unless new_socket.gets.chomp! == "new_tunnel"
              @tunnels[new_socket.fileno] = ::Client::Tunnel.new(new_socket, tunnel.local_host_client)
              tunnel.close
            end
          rescue StandardError => e
            Utils.log.error(e.message)
            Utils.log.error(e.backtrace)
          end
        end
      end
    end

    def control
      loop do
        begin
          Utils.log.debug("start tunnels")
          Utils.log.debug(@tunnels.inspect)
          sockets = IO.select(@tunnels.reject { |fileno, tunnel| tunnel.closed? || tunnel.busy }.values.map { |tunnel| tunnel.socket }, nil, nil, 1)

          next if sockets.nil?

          socket = sockets[0][0]
          tunnel = @tunnels[socket.fileno]

          Thread.start {
            tunnel.dispatch do |data|
              if data.start_with?("GET ")
                proxy(data, tunnel)
              else
                Utils.log.debug("invalid request")
                tunnel.puts("invalid request")
              end
            end
          }.join

        rescue StandardError => e
          Utils.log.error(e.message)
          Utils.log.error(e.backtrace)
          sleep 3
          next
        end
      end
    end

    def proxy(input, tunnel)
      Utils.log.debug("start proxy")
      begin
        tunnel.proxy(input)
      rescue StandardError => e
        Utils.log.error(e.message)
        Utils.log.error(e.backtrace)
        #proxy(input, tunnel)
      ensure
        tunnel.local_host_client.close
        tunnel.local_host_client = TCPSocket.open(@local_host, @local_port)
      end
    end

    def heartbeat
      loop do
        sleep 5
        heartbeat_tunnel
      end
    end

  end

end

opt = OptionParser.new
config_file_path = nil
opt.on('-c', '--config_path STRING') {|v| config_file_path = v }
opt.parse(ARGV)

Utils.config_loader = Utils::ConfigLoader.new(Utils::ENV::CLIENT, config_file_path)

Utils.log = Utils::Logger.new
Utils.log.debug(Utils.config_loader.config)

Client::Main.new.main()
