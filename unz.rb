#!/usr/bin/env ruby
# unz unzips zips (and other things)

require 'optparse'
require 'set'
require 'open3'

class Unz
  BANNER = "usage: unz filename [out]"

  class ArchiveError < Exception
  end

  class Archive
    def initialize filename
      @filename = filename
      raise ArchiveError, "File does not exist" if !File.exists?(@filename)

      @kind = case @filename
        when /\.t(ar\.)?gz$/ then :tar_gz
        when /\.tar\.bz2$/ then :tar_bz2
        when /\.zip$/ then :zip
        else raise ArchiveError, "Unknown archive"
      end
    end

    def unpack destination, options
      send("unpack_#{@kind}", destination, options)
    end

    def unpack_tar_gz destination, options
      unpack_tar(destination, options, 'z')
    end

    def unpack_tar_bz2 destination, options
      unpack_tar(destination, options, 'j')
    end

    def unpack_tar destination, options, mode
      toplevel = find_toplevel(%W{tar tf #{@filename}}) { |line|
        $1 if line =~ /^([^\/]*\/?)/
      }
      folder, implicit = find_target_folder(toplevel, destination, options[:single_target])
      puts "Unpacking tar into #{folder}" if options[:verbose]
      Dir.mkdir(folder) if !implicit
      execute(%W{
        tar x#{mode}#{options[:verbose] ? 'v': ''}
        -C #{implicit ? '.' : folder}
        -f #{@filename}
      }, :stderr) { |msg| puts msg[2..-1] }
    end

    def unpack_zip destination, options
      toplevel = find_toplevel(%W{unzip -l #{@filename}}) { |line|
        $1 if line =~ /^\s*\d+\s+\d+-\d+-\d+\s+\d+:\d+\s+([^\/]*\/?)/
      }
      folder, implicit = find_target_folder(toplevel, destination, options[:single_target])
      puts "Unpacking zip into #{folder}" if options[:verbose]
      Dir.mkdir(folder) if !implicit
      execute(%W{
        unzip -o
        -d #{implicit ? '.' : folder}
        #{@filename}
      }, :stdout) do |msg|
        puts $2 if options[:verbose] && msg =~ /^\s*(extracting|inflating):\s+(.*?)\s*$/
      end
    end

    def find_target_folder toplevel, destination=nil, single=true
      return File.expand_path('') if not single
      return [destination, false] if !destination.nil?
      return [File.expand_path(toplevel[0] =~ /\/$/ ? toplevel[0][0..-1] : ''), true] \
             if toplevel.length == 1
      [@filename =~ /(.*?)\.(t(ar\.)?gz|zip|bz2)$/ ? $1 : @filename + '_out', false]
    end

    def find_toplevel cmd, &blk
      toplevel = Set.new
      execute(cmd) do |line|
        item = blk.call(line)
        toplevel << item if item
      end
      toplevel.to_a
    end

    def execute cmd, forwarded=:stdout, &blk
      Open3.popen3(*cmd) do |stdin, stdout, stderr|
        stdin.close
        begin
          $stderr.print(stderr.read) if forwarded != :stderr
          stream = {:stdout => stdout, :stderr => stderr}[forwarded]
          while !stream.eof?
            blk.call(stream.readline[0..-2])
          end if blk
        ensure
          stderr.close
          stdout.close
        end
      end
    end
  end

  def initialize source, destination=nil
    @source = Archive.new(source)
    @destination = destination
  end

  def run options
    @source.unpack(@destination, options)
  end

  def self.fail_with message
    puts BANNER
    $stderr.puts(message)
    exit
  end

  def self.main
    options = {:verbose => false, :single_target => false}
    parser = OptionParser.new do |op|
      op.banner = BANNER
      op.on("-v", "--verbose", "Run in verbose mode") do
        options[:verbose] = true
      end
      op.on("-S", "--[no-]single", "Disable creation of single folder on unpack") do |val|
        options[:single_target] = val
      end
      op.on("--help", "Show this help screen") do
        puts op
        exit
      end
    end

    begin
      args = parser.parse(ARGV)
    rescue OptionParser::InvalidOption => e
      puts BANNER
      $stderr.puts(e)
      exit
    end

    (puts BANNER; exit) if args.length == 0
    fail_with("Too many arguments") if args.length > 2
    begin
      self.new(*args).run(options)
    rescue ArchiveError => e
      $stderr.puts(e)
    end
  end

end


Unz.main if __FILE__ == $0
