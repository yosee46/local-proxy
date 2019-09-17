require "socket"
require 'bundler/inline'
require "timeout"

gemfile do
  source 'https://rubygems.org'
  gem 'timers'
end


class Message
  attr_accessor :req_id
end

class ClientModel
  attr_accessor :local_host_client, :tunnels, :mutexes, :map_mutex

  REMOTE_ADDR = "*******"
  REMOTE_PORT = 80
  LOCAL_ADDR = "localhost"
  LOCAL_PORT = 3000

  def initialize
    create_connection
  end

  def create_connection
    @local_host_client = TCPSocket.open(LOCAL_ADDR, LOCAL_PORT)
    @tunnels = Hash.new
    @mutexes = Hash.new
    @ping_history = Hash.new
    @map_mutex = Mutex.new
    8.times do
      socket = TCPSocket.open(REMOTE_ADDR, REMOTE_PORT)
      socket.puts("tunnel+#{socket.fileno}")
      if IO.select([socket], nil, nil, 2)
        if socket.gets.chomp! == "new_tunnel"
          p "establish new tunnel"
          @tunnels[socket.fileno] = socket
          @mutexes[socket.fileno] = Mutex.new
        end
      end
    end
  end

  def heatbeat_tunnel
    copy = @tunnels.dup
    copy.each do |fileno, tunnel|
      p "before ping"
      @mutexes[fileno].synchronize do

        last_ping = @ping_history[fileno]
        if last_ping.nil? || last_ping + 20 > Time.now
          p "ping"
          tunnel.puts("ping")
          next
        end

        begin
          new_tunnel = TCPSocket.open(REMOTE_ADDR, REMOTE_PORT)
          new_tunnel.puts("tunnel+#{new_tunnel.fileno}+#{fileno}")
          if IO.select([new_tunnel], nil, nil, 3)
            p "establish new tunnel"
            next unless new_tunnel.gets.chomp! == "new_tunnel"

            @mutexes.delete(fileno)
            @mutexes[new_tunnel.fileno] = Mutex.new
            @tunnels.delete(fileno)
            @tunnels[new_tunnel.fileno] = new_tunnel
            tunnel.close
          end
        rescue StandardError => e
          p e
        end
      end
    end
  end

  def control
    while true
      datas = []
      tunnels = IO.select(@tunnels.reject { |fileno, tunnel| tunnel.closed? }.values, nil, nil, 1)

      next if tunnels.nil?

      tunnel = tunnels[0][0]
      @mutexes[tunnel.fileno].synchronize do
        next if tunnel.closed?
        while IO.select([tunnel], nil, nil, 1)
          datas << tunnel.gets
        end
        next if datas.empty?
        data = datas.join
        p data

        if data.chomp == "pong"
          @tunnels[tunnel.fileno] = tunnel
          @ping_history[tunnel.fileno] = Time.now
          p "pong"
        else
          if data.start_with?("pong")
            data.slice!(0, 5)
          elsif data.end_with?("pong\n")
            data.slice!(data.size - 5, 5)
          end

          p "reformat data"
          p data

          if data.start_with?("GET ")
            proxy(data, tunnel)
          else
            p "invalid"
            tunnel.puts("invalid request")
          end
        end
      end
    end
  end

  def proxy(input, tunnel)
    p "proxy"
    datas = []
    begin
      @local_host_client.write(input)

      # I do not know why IO.select makes this code slower
      while buffer = @local_host_client.gets
        if buffer.nil?
          break
        end
        datas << buffer
      end
    rescue StandardError => e
      p e
      @local_host_client.close
      @local_host_client = TCPSocket.open(LOCAL_ADDR, LOCAL_PORT)
      proxy(input, tunnel)
    ensure
      @local_host_client.close
      @local_host_client = TCPSocket.open(LOCAL_ADDR, LOCAL_PORT)
    end
    data = datas.join
    p data
    tunnel.puts(data)
  end

  def heatbeat
    loop do
      #TODO 短くしすぎるとループで捕まって新規のコネクション晴れなくなる問題
      sleep 5
      heatbeat_tunnel
    end
  end
end

class Main
  def main

    client_model = ClientModel.new
    threads = []
    threads << Thread.start { client_model.heatbeat }
    threads << Thread.start do ||
      begin
        client_model.control
      rescue StandardError => e
        p e
        client_model.control
      end
    end
    threads.each { |thr| thr.join }

    # HEADERでHTTPであることを指定しないとELBで400エラーになる？
    message = Message.new
    message.req_id = "test_1"

  end
end

Main.new.main

