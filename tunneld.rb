require "socket"
require 'thread'

port = 80
server = TCPServer.open(port)
tunnels = Hash.new
mutexes = Hash.new
url_sockets = Hash.new

fileno_hash = Hash.new

Thread.start do
  loop do
    begin
      while tunnels_data = IO.select(tunnels.values.reject { |tunnel| tunnel.closed? }, nil, nil, 1)
        tunnel = tunnels_data[0][0]
        p fileno_hash
        p tunnel.fileno
        fileno = fileno_hash[tunnel.fileno]
        datas = []
        while IO.select [tunnel], nil, nil, 1
          datas << tunnel.gets
        end
        next if datas.empty?
        data = datas.join

        if data.chomp.start_with?("ping")
          p "ping"
          tunnel.puts("pong")
        end
      end
    rescue StandardError => e
      p e
    end
  end
end

while true
  Thread.start(server.accept) do |socket|
    p "insocket"
    begin
      datas = []
      while IO.select [socket], nil, nil, 1
        datas << socket.gets
      end
      data = datas.join
      p "data"

      if data.start_with?("tunnel")
        array = data.chomp!.split('+')
        fileno = array[1]
        old_fileno = array[2]
        p "tunnel"

        unless old_fileno.nil?
          mutexes[old_fileno].synchronize do
            begin
              p "old_tunnels"
              p tunnels
              old_tunnel = tunnels[old_fileno]
              unless old_tunnel.nil?
                old_tunnel.close
              end
            rescue StandardError => e
              p e
            end
          end
        end

        p "new tunnel"
        p tunnels
        socket.puts("new_tunnel")
        tunnels[fileno] = socket
        fileno_hash[socket.fileno] = fileno
        mutexes[fileno] = Mutex.new


      elsif data.start_with?("GET ") and !data.start_with?("GET /nginx_status")
        p data
        p "process get"
        while writable_tunnel = IO.select(nil, tunnels.values.reject { |tunnel| tunnel.closed? }, nil, 1)
          p "process writable tunnel"
          tunnel = writable_tunnel[1][0]
          p tunnel

          next if tunnel.nil?
          p "process tunnel"
          fileno = fileno_hash[tunnel.fileno]
          mutexes[fileno].synchronize do
            begin
              p "tunnel.puts process"
              next if tunnel.closed?
              tunnel.puts(data)
              if IO.select [tunnel], nil, nil, 10
                p "save socket"
                p socket
                url_sockets[fileno] = socket

                loop do
                  datas = []
                  while IO.select [tunnel], nil, nil, 1
                    datas << tunnel.gets
                  end
                  next if datas.empty?
                  data = datas.join

                  if data.chomp.start_with?("ping")
                    tunnel.puts("pong")
                    p "ping"
                    next
                  end

                  p "puts socket to url"
                  socket.puts(data)
                  p "close socket after to url"
                  socket.close()
                  break
                end

              else
                socket.puts(data)
                socket.close()
                p "url socket close"
              end
            rescue StandardError => e
              p e
              next
            end
          end
          break
        end
      end
    rescue StandardError => e
      p e
    end

  end
end

server.close