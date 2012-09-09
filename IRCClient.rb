# Author: Lurker_pas
# Simple console based IRC Client written in Ruby
#
# see www.lurkersburrow.wordpress.com
#
# Supports: 
# * basic chat (channel/private)
# * basic dcc send (with resume and queueing ability)
# * non-private chat recording
#
# Based on: simple IRC bot from http://snippets.dzone.com/posts/show/1785
# Created 2007 10 10
# Update 2007 10 14 - Added basic DCC SEND support
# Update 2007 10 15 - Added queue and record ability
# Update 2008 10 20 - Major update:
#                     * added autoresume, talk mode and queue listing
#                     * removed dccget
#                     * added additional info during download
# Update 2008 10 28 - raise exception on speed = 0
# Update 2009 02 21 - Major update:
#                     * added color console
#                     * added dccqueueremove
#                     * added echo/dontecho
#                     * added batch version of dccqueue
#                     * removed ping pongs
#                     * refactored version
#                     * added users and channels
#                     * added msg dontmsg
# Update 2009 02 22 - Added enviroment variables and notice
#
#
#to do:
#reconecting to IRC server if connection is broken
#loading download list

require "socket"
require "monitor"
require "timeout"

def version
  "v2.100"
end

def cclear
  print "\033[0m\033[37m";
  $stdout.flush
end

def cerror
  print "\033[1m\033[31m";
end

def csuccess
  print "\033[1m\033[32m";
end

def cusers
  print "\033[2m\033[32m";
end

def cnotice
  print "\033[1m\033[36m";
end

def cinfo
  print "\033[2m\033[36m";
end

def ctalk
  print "\033[1m\033[37m";
end

def cmessage
  print "\033[2m\033[34m";
end

def cwelcome
  print "\033[1m\033[34m";
end

def ccommand
  print "\033[2m\033[35m";
end

class IRCDCC
      attr_writer :requestresume
      attr_writer :queuecooldown
      attr_reader :queuecooldown
      attr_writer :autoresume
      attr_writer :autoresumemaxretries
      attr_writer :autoresumecooldown
      
    def initialize()      
      @allowed = Hash.new
      @blocks = Hash.new
      @blocks.extend(MonitorMixin) 
      @blockschanged = @blocks.new_cond
      @requestresume = false
      @queue = Array.new
      @queue.extend(MonitorMixin)
      @queueready = @queue.new_cond      
      @bot = Hash.new
      @bot.extend(MonitorMixin)
      @botdone = @bot.new_cond
      @queuecooldown = 3
      @currentqueuebot = ""
      @currentpack = 0
      @autoresume = false
      @autoresumecooldown = 60
      @autoresumemaxretries = 4
      @autoresumeretries = 0;
    end
    def initsocket(socket)
      @ircsocket = socket
    end
    def addallowed(name)
      @allowed[name] = true      
    end
    def removeallowed(name)
      @allowed[name] = false      
    end
    def isallowed(name)
      result = false
      if (@allowed[name]==true)
        result = true
      end
      result
    end
    def min(x,y)
      if (x < y)
        x
      else
        y
      end
      
    end
    
    def addtoqueue(bot,pack)
     @queue.synchronize do
       @queue.push([bot,pack])
       @queueready.signal
     end      
    end
    def cancelcurrentbot
      @bot.synchronize do
          @bot[@currentqueuebot] = true
          @botdone.signal
        end      
       @autoresumeretries = 0
    end
    
    def remove(item)
      @queue.synchronize do
        @queue.delete_at(item)
      end
    end
    
    def clearqueue()
      @queue.synchronize do
        @queue.clear
      end
    end
    
    def listqueue()
      @queue.synchronize do
        cinfo
        i = 0;
        while i < @queue.length
          puts "Queue(#{i}): bot - #{@queue[i][0].to_s()}; pack - #{@queue[i][1].to_s()};"
          i = i+1;
        end
        if (@queue.length==0) then
          puts "Queue is empty"
        end
        cclear
      end
    end
    
    def queuethread()
      botname = ""
      packnumber = ""      
      while true
        cinfo
        puts "Queue: waiting for items"
        cclear
        @queue.synchronize do
          @queueready.wait_while {@queue.length < 1}
          botname = @queue[0][0]
          packnumber = @queue[0][1]
          @queue.shift          
        end
        @currentqueuebot = botname.dup
        @currentpack = packnumber
        cinfo
        puts "Queue: #{botname} > #{packnumber}"
        cclear
        #request pack
        s = "PRIVMSG #{botname} :xdcc send ##{packnumber}"
        cinfo
        puts "--> #{s}"
        cclear
        @ircsocket.print "#{s}\r\n"
        #wait until everything is downloaded
        cinfo
        puts "Queue: downloading..."
        cclear
        @bot.synchronize do
          @bot[botname] = false
          @botdone.wait_while { @bot[botname]==false}
        end
        cinfo
        puts "Queue: cooling down"
        cclear
        sleep(@queuecooldown)                       
        
      end
    end
    
    def negotiateresume(bot,name,port,existingfilesize)
      cinfo
      puts "Waiting for resume on #{name}"
      s = "PRIVMSG #{bot} :\001DCC RESUME #{name} #{port} #{existingfilesize}\001"
      puts "--> #{s}"
      cclear
      @ircsocket.print "#{s}\r\n" 
      @blocks.synchronize do
       @blocks[name] = false
       @blockschanged.wait_while {@blocks[name] == false}
      end
      csuccess
      puts "Resume acceptance on #{name} acknowledged"
      cclear
      existingfilesize
      
    end
    
    def downloadthread(bot,name,address,port,filesize)
      cinfo
      puts "Downloading #{name} (#{filesize} bytes) from #{bot}@#{address}:#{port}"      
      cclear
      packetlength = 2048
      bytesleft = filesize
      fname = name.gsub(/"|\s|\\/,"")      
      
      existingfilesize = 0  
      if (File.exists?(fname) && @requestresume && (File.size?(fname) < bytesleft)) then
        existingfilesize = File.size?(fname)
        negotiateresume(bot,name,port,existingfilesize)
        file = File.new(fname,"a")
      else
        if (File.exists?(fname) && (@requestresume) && (File.size?(fname) >= bytesleft)) then
          existingfilesize = File.size?(fname)
          file = File.new(fname,"a")
        else
          file = File.new(fname,"w")
        end
      end      
      bytesleft = filesize-existingfilesize      
      i = 0
      if (!file) then
        cerror
        puts "File IO Error"
        cclear
        return
      end
      
      begin
      socket = TCPSocket.open(address, port)
      if (!socket) then
        cerror
        puts "Socket IO Error"
        cclear
        return
      end
      cinfo
      puts "Downloading #{name}: #{bytesleft} bytes left..."
      cclear
      chunkcounter = 0
      reftime = Time.now()
      while bytesleft > 0
        killme = true
        Timeout.timeout(30) do
          chunk = min(packetlength,bytesleft)        
          packet = socket.recv(chunk)
          file.write(packet)        
          bytesleft = bytesleft - packet.length
          chunkcounter = chunkcounter + packet.length
          i = i +1
          if (i > 4000)
            i = 0
            cinfo
            puts "Downloading #{name} at #{(((chunkcounter/1024 )/ (Time.now()-reftime))).to_i} kbps: #{bytesleft/1000} kb (#{(bytesleft*100)/filesize} percent) left..."        
            cclear
            reftime = Time.now()
            if (chunkcounter == 0) then
             raise "Connection is broken"
            end
            chunkcounter =0
          end
          killme = false
        end
        if (killme) then
          raise "Connection is broken"
        end
      end
      socket.close
      file.close
      csuccess
      puts "Downloading #{name} done"
      cclear
      @autoresumeretries = 0;
      @bot.synchronize do
        @bot[bot] = true
        @botdone.signal
      end
      
      rescue Exception => e
        begin
          socket.close
          file.close
        rescue
        end
      cerror
      puts "Downloading #{name} finished with error"+e
      cclear
      @autoresumeretries=@autoresumeretries+1;
      if ((@autoresume)&&(@autoresumeretries<=@autoresumemaxretries)) then 
        sleep(@autoresumecooldown)
        @queue.synchronize do
         @queue.push([@currentqueuebot,@currentpack])
         @queueready.signal
        end
      end
      @bot.synchronize do
        @bot[bot] = true
        @botdone.signal
      end  
      end
    end
    
    def extractaddress(intaddress)
      #Translate address
      binaddr = intaddress
      ip0 = binaddr%256
      binaddr = binaddr >> 8
      ip1 = binaddr%256
      binaddr = binaddr >> 8
      ip2 = binaddr%256
      binaddr = binaddr >> 8
      ip3 = binaddr%256
      ipaddress = "#{ip3}.#{ip2}.#{ip1}.#{ip0}"        
      return ipaddress
    end
    
    def downloadblocking(bot,name,address,port,filesize)
      ipaddress = extractaddress(address)
      #create downloading thread            
      downloadthread(bot,name,ipaddress,port,filesize)
      
    end
    
    def download(bot,name,address,port,filesize)
      
      ipaddress = extractaddress(address)
      #create downloading thread      
      dt = Thread.new do
        downloadthread(bot,name,ipaddress,port,filesize)
      end
      
    end
    def processdccmsg(name,msg)
      message = msg.strip
      if  message =~ /DCC ACCEPT (\".*\"|\S*) (\d*) (\d*)/
        csuccess
        puts "Resume of #{$1} accepted"
        cclear
        @blocks.synchronize do
          @blocks[$1] = true
          @blockschanged.signal
        end        
        return
      end
      if  message =~ /DCC SEND (\".*\"|\S*) (\d*) (\d*) (\d*)/
        cinfo
        print "DCC Send received from #{name} - "
        if isallowed(name)
          csuccess
          puts " accepting"
          download(name,$1,($2).to_i,($3).to_i,($4).to_i)
        else
          cclear
          puts " refusing"
        end
        cclear
        
        return
      end
      cinfo
      puts "Unknown dcc message"
      cclear
    end
end

class IRCClient
    
    def initialize(server, port, nick)
        @echo = false
        @server = server
        @port = port
        @nick = nick
        @channel = ""
        @dead = false
        @raw = false
        @quitmessage = "Disconnecting..."
        @dcc = IRCDCC.new()        
        @recording = false
        @talk = false
        @msg = true
        @listing = false
    end
    
    def initializerecording(filename)
      @recording = true
      @recordingfile = File.new(filename,"w")      
    end
    
    def shutdownrecording()
      if (@recording) then
        @recording = false
        @recordingfile.close
      end
    end
    
    def print_help
      cinfo
      puts "IRC Client by Lurker_pas"
      puts "see www.lurkersburrow.wordpress.com"
      puts "Available commands:"
      puts ">> help - shows this help"
      puts ">> say *message* - sends specified message to channel"
      puts ">> notice *message* - sends specified notice to channel"
      puts ">> psay *nick* *message* - sends specified message to specified client"
      puts ">> quit - quits"
      puts ">> channels - lists channels"
      puts ">> users - lists users on the active channel"
      puts ">> mode *modechange* - sets user mode ([+|-][i|w|s|o])"
      puts ">> join *channel* - join specified channel"
      puts ">> leave *channel* - leave specified channel"
      puts ">> context *channel* - set the channel you want to talk to"
      puts ">> /*command* - direct IRC protocol command (without validation)"
      puts ">> raw - start showing all unprocessed messages from server"
      puts ">> unraw - stop showing all unprocessed messages from server"
      puts ">> record *filename* - start recording channel messages to the specified file"
      puts ">> dontrecord - stop recording"
      puts ">> dccaccept *name* - accept all dcc sends from *name*"
      puts ">> dccdeny *name* - deny all dcc sends from *name*"
      puts ">> dccrequestresume - request resume if file sent by dcc send exists"
      puts ">> dccdontrequestresume - dont request resume"
      puts ">> dcclist *name* - send xdcc list command to *name*"
      puts ">> dccinfo *name* *pack* - request info from *name* on pack number *pack*"
      puts ">> dccqueue *name* *pack* - add pack *pack* from *name* to the auto-download"
      puts ">>           queue"
      puts ">> dccqueue *name* *start*:*stop*:*step* - add packs from *start* to *stop*"
      puts ">>           stepping by *step* from *name* to the auto-download queue"
      puts ">> dccqueueclear - clear the auto-download queue"
      puts ">> dccqueueremove *item*- remove the given element from the auto-download queue"
      puts ">> dccqueuecancel - cancel the current download by the auto-download queue"
      puts ">> dccqueuecooldown *seconds* - set the 'after-download' cooldown for "
      puts">>            *seconds* seconds"
      puts ">> dccqueuelist - list contents of the download queue"
      puts ">> dccautoresume - turn on download auto-retry"
      puts ">> dccdontautoresume - turn off download auto-retry"
      puts ">> dccautoresumecooldown *seconds* - set the 'auto-resume' cooldown for "
      puts ">>           *seconds* seconds"
      puts ">> dccautoresumemaxretries *number* - set the number of 'auto-resume' "
      puts ">>           retries to *number*"
      puts ">> talk - enter talk mode"
      puts ">> !talk - leave talk mode"
      puts ">> echo - print all messages sent to the IRC server"
      puts ">> dontecho - dont print the messages sent to the IRC server"
      puts ">> msg - print special messages sent from the IRC server"
      puts ">> dontmsg - dont print special messages sent from the IRC server"
      puts ">> NOTE : *record* records only channel messages from subscribed channels"
      puts ">>           - no private chats are recorded"
      puts ">> NOTE : *dccaccept name* must be invoked >>before<< the actual download"
      puts ">>           occurs (before dccget or dccqueue...)"
      puts ">> NOTE : queue cooldown is given in (integer) seconds "
      puts "Enjoy"
      cclear
    end
    
    def send(s)      
        if (@echo)
          cinfo
          puts "--> #{s}"
          cclear
        end
        @irc.print "#{s}\r\n" 
    end
    def connect()    
        cinfo
        puts "Connecting to server #{@server} at port #{@port}..."
        @irc = TCPSocket.open(@server, @port)  
        @dcc.initsocket(@irc)
        puts "Setting Nick to #{@nick} and User to #{@nick} user..."
        cclear
        send "USER #{@nick} server #{@server} :#{@nick} user"        
        send "Nick #{@nick}"        
    end
    
    def handleservermessage(s)        
        if @raw then
           puts s
        end
        case s.strip                    
            when /^PING :(.+)$/i
                # makes no point puts "[ Server ping ]"
                send "PONG :#{$1}"
            when /^:(.+?)!(.+?)@(.+?)\sPRIVMSG\s.+\s:[\001]PING (.+)[\001]$/i
                cinfo
                puts "[ CTCP PING from #{$1}!#{$2}@#{$3} ]"
                cclear
                send "NOTICE #{$1} :\001PING #{$4}\001"
            when /^:(.+?)!(.+?)@(.+?)\sPRIVMSG\s.+\s:[\001]VERSION[\001]$/i
                cinfo
                puts "[ CTCP VERSION from #{$1}!#{$2}@#{$3} ]"
                cclear
                send "NOTICE #{$1} :\001VERSION Ruby-IRCClient "+version+"\001"            
            when /^:(\S*)!(.)* PRIVMSG #{@nick} :(.*)$/                
                ctalk
                puts "\033[21m"+$1+"\033[24m >>*>> "+$3
                sendername = $1.strip
                sendermsg = $3.strip
                if (sendermsg =~ /DCC (.*)/)
                  cinfo
                  puts "DCC message received from #{sendername}"
                  @dcc.processdccmsg(sendername,sendermsg)
                end
                cclear
            when /^:(\S*)!(.)* PRIVMSG (\S+) :(.*)$/                
                if @recording then
                  @recordingfile.write("#{$1}@#{$3} >> #{$4}\n")
                end
                ctalk
                puts "\033[21m"+$1+"@"+$3+"\033[24m >> "+$4
                cclear
            when /^:(\S*)!(.)* NOTICE (.*)$/                
                cnotice
                puts "\033[21m#{$1} NOTICE\033[24m >> #{$3}"                
                cclear
            when  /^:(\S*)!(.*) JOIN (\S+)/
                cnotice
                puts $1+" (#{$2}) joined "+$3
                cclear
            when  /^:(\S*)!(.*) PART (\S*)/
                cnotice
                puts "#{$1} (#{$2}) left #{$3}"
                cclear
            when  /^:(\S*)!(.*) QUIT(.*)/
                  cnotice
                  user = $1
                  address = $2
                  tail = $3
                  if (tail =~ /:(.*)/)
                    puts "#{user} (#{address}) quit - #{$1}"
                  else
                    puts "#{user} (#{address}) quit"
                  end    
                 cclear
            when /^:(\S+) (\d+) (\S+) (\S) (\S+) (.*):(.*)$/i                
                cusers
                  if (@msg)
                    puts "USERS@#{$5} >> #{$6} : #{$7}"
                  end                  
                cclear        
            when /^:(\S+) (\d+) (\S+) (\S+) (.*):(.*)$/i                
                cmessage
                  if (@msg)
                    puts "MSG >> #{$4} >> #{$5} : #{$6}"
                  end                  
                cclear  
        end
    end
    
    def user_handler(lock)
      while true                                  
         cclear
          s = gets          

        if @talk then
          if s=~ /^!talk/ then
            cinfo
            puts "Leaving talk mode"
            cclear
            @talk = false
            next
          end
          lock.synchronize do
              send "PRIVMSG #{@channel} :"+s
            end         
            next
        end
        
        if s=~ /^channels/ then            
            lock.synchronize do
              send "LIST"
            end         
            next
          end   
        
        if s=~ /^users/ then            
            lock.synchronize do
              send "WHO #{@channel}"
            end         
            next
          end   
        
        if s=~ /^notice / then            
            lock.synchronize do
              send "NOTICE #{@channel} :"+s.gsub(/^notice /,"")
            end         
            next
          end                       
        
          if s=~ /^say / then
            if @recording then
                  @recordingfile.write("#{@nick}@#{@channel} >> #{s.gsub(/^say /,"")}\n")
                end
            lock.synchronize do
              send "PRIVMSG #{@channel} :"+s.gsub(/^say /,"")
            end         
            next
          end                       
        
          if s=~ /^psay (\S*) (.*)/ then
            lock.synchronize do
              send "PRIVMSG "+$1+" :"+$2
            end
            next
          end
          
          if s=~ /^context (.+)/ then
            @channel = $1
            if !(@channel =~ /^#.*/) then
              @channel = "#"+@channel
            end            
            next
          end
        
          if s=~ /^join (.+)/ then
            @channel = $1
            if !(@channel =~ /^#.*/) then
              @channel = "#"+@channel
            end
            lock.synchronize do
              send "JOIN #{@channel}"
            end
            next
          end
        
          if s=~ /^leave (.+)/ then
            channelname = $1
            if !(channelname =~ /^#.*/) then
              channelname = "#"+channelname
            end
            lock.synchronize do
              send "PART #{channelname}"
            end
            next
          end
        
          if s=~ /^raw/ then
            @raw = true
            cinfo
            puts "RAW mode ON"
            cclear
            next
          end       
          
          if s=~ /^unraw/ then
            @raw = false
            cinfo
            puts "RAW mode OFF"
            cclear
            next
          end       
        
          if s=~ /^mode ([+-][iwso]+)/ then
            lock.synchronize do
              send "MODE #{@nick} :"+$1
            end         
            next
          end        
        
          if s=~ /^quit/ then
            lock.synchronize do
              send "QUIT :"+@quitmessage
            end         
            @dead = true
            break            
          end
          
          if s=~ /^\/(.*)/ then
            lock.synchronize do
              send $1.chomp
            end            
            next            
          end
          
          if s=~ /^help/ then
            print_help
            next
          end
          
          if s =~ /^record (\S*)/ then
            initializerecording($1)
            cinfo
            puts "Recording ON (#{$1})"
            cclear
            next
          end
          
          if s =~ /^dontrecord/ then
            shutdownrecording()
            cinfo
            puts "Recording OFF"
            cclear
            next
          end
          
        if s =~ /^msg/ then
            @msg = true
            cinfo
            puts "Messages ON"
            cclear
            next
          end
          
          if s =~ /^dontmsg/ then
            @msg = false
            cinfo
            puts "Messages OFF"
            cclear
            next
          end
        
          if s =~ /^echo/ then
            @echo = true
            cinfo
            puts "Echo ON"
            cclear
            next
          end
          
          if s =~ /^dontecho/ then
            @echo = false
            cinfo
            puts "Echo OFF"
            cclear
            next
          end
        
          if s=~ /^dccaccept (\S*)/ then
            @dcc.addallowed($1)
            cinfo
            puts "Added #{$1} to allowed list"
            cclear
            next
          end
          
          if s=~ /^dccdeny (\S*)/ then
            @dcc.removeallowed($1)
            cinfo
            puts "Removed #{$1} from allowed list"
            cclear
            next
          end
          
          if s=~ /^dccrequestresume/ then
            @dcc.requestresume = true
            cinfo
            puts "DCC Resume Request ON"
            cclear
            next
          end
          if s=~ /^dccdontrequestresume/ then
            @dcc.requestresume = false
            cinfo
            puts "DCC Resume Request OFF"
            cclear
            next
          end
          if s=~ /^dccdontautoresume/ then
            @dcc.autoresume = false
            cinfo
            puts "DCC Auto Resume OFF"
            cclear
            next
          end
          if s=~ /^dccautoresumecooldown (\d*)/
            @dcc.autoresumecooldown = ($1).to_i()   
            cinfo
            puts "DCC Auto Resume cooldown set to #{($1).to_i()}"
            cclear
            next
          end
          if s=~ /^dccautoresumemaxretries (\d*)/
            @dcc.autoresumemaxretries = ($1).to_i()         
            cinfo
            puts "DCC Auto Resume max retries set to #{($1).to_i()}"  
            cclear
          next
          end
          if s=~ /^dccautoresume/ then
            @dcc.autoresume = true
            cinfo
            puts "DCC Auto Resume ON"
            cclear
            next
          end
          if s=~ /^talk/
            @talk = true
            cinfo
            puts "Entering talk mode"
            cclear
            next
          end
          if s=~ /^dcclist (\S*)/
            lock.synchronize do
              send "PRIVMSG #{$1} :xdcc list"
            end         
            next
          end
          if s=~ /^dccqueuelist/ then
            @dcc.listqueue()
            next
          end
          if s=~ /^dccinfo (\S*) (\d*)/
            lock.synchronize do
              send "PRIVMSG #{$1} :xdcc info ##{$2}"
            end         
            next
          end          
          if s=~ /^dccqueue (\S*) (\d*):(\d*):(\d*)/
            cinfo  
            start = ($2).to_i;
            stop = ($3).to_i;
            step = ($4).to_i;
            start.step(stop, step) { |i|  
              @dcc.addtoqueue($1,i)            
              puts "Added #{$1} > pack #{i} to queue"
            }
            cclear
            next
          end  
          if s=~ /^dccqueue (\S*) (\d*)/
            @dcc.addtoqueue($1,($2).to_i)
            cinfo
            puts "Added #{$1} > pack #{$2} to queue"
            cclear
            next
          end
          if s=~ /^dccqueueremove (\d*)/
            @dcc.remove(($1).to_i)
            cinfo
            puts "Removing item #{($1).to_i} from queue"
            cclear
            next
          end
          if s=~ /^dccqueueclear/
            @dcc.clearqueue()
            cinfo
            puts "Queue cleared"
            cclear
            next
          end
          
          if s=~ /^dccqueuecooldown (\d*)/
            @dcc.queuecooldown = ($1).to_i
            cinfo
            puts "Queue cooldown set to #{@dcc.queuecooldown}"
            cclear
            next 
          end
          if s=~ /^dccqueuecancel/
            @dcc.cancelcurrentbot
            cinfo
            puts "Cancelling current download"
            cclear
            next
          end
        cerror
        puts "Invalid command"
        cclear
         
      end
    end
    
    def main_loop()        
       lock = Monitor.new  
      
       input = Thread.new do
          user_handler(lock)          
       end
       
       downloadqueue = Thread.new do
         @dcc.queuethread()
       end
      
        while true
          ready = select([@irc],nil, nil,1)                    
            break if @dead
            next if !ready
           
            for rs in ready[0]
                if rs == @irc then
                      return if @irc.eof                    
                      lock.synchronize do          
                          s = @irc.readline.chomp
                          handleservermessage(s)
                      end
                    
                end
                
                
            end
        end
        input.join
        shutdownrecording()
        @irc.close
        
      end
    
cwelcome
puts "MKE Ruby IRC Client "+version
puts "@see lurkersburrow.wordpress.com"
if (!ENV['IRCSERVER'])
puts "Enter server name:"
  cclear
  ccommand
  server_name = gets.chomp  
else
  server_name = ENV['IRCSERVER']
end

    
if (!ENV['IRCNICK'])
  cwelcome
  puts "Enter nick:"
  cclear
  ccommand
  nick = gets.chomp
else
  nick = ENV['IRCNICK']
end        
cclear

if (!ENV['IRCPORT'])
  port = 6667
else
  port = ENV['IRCPORT']
end            
    
begin

irc = IRCClient.new(server_name, port,nick)
irc.connect()
irc.main_loop()
rescue Exception => e
    cerror
    puts "Exception while executing "+e    
    cclear
end
end
