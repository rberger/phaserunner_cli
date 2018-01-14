require 'gli'
require 'json'
require 'pp'

module Phaserunner
  # Handle Ctl-C exit
  trap "SIGINT" do
    puts "Exiting"
    exit 130
  end

  class Cli
    attr_reader :modbus
    attr_reader :dict
    attr_reader :loop
    attr_reader :quiet
    attr_reader :phaserunnerOutFd

    include GLI::App

    def main
      program_desc 'Read values from the Grin PhaseRunner Controller primarily for logging'

      version Phaserunner::VERSION

      subcommand_option_handling :normal
      arguments :strict
      sort_help :manually

      desc 'Serial (USB) device'
      default_value '/dev/ttyUSB0'
      arg 'tty'
      flag [:t, :tty]

      desc 'Serial port baudrate'
      default_value 115200
      arg 'baudrate'
      flag [:b, :baudrate]

      desc 'Modbus slave ID'
      default_value 1
      arg 'slave_id'
      flag [:s, :slave_id]

      desc 'Path to json file that contains Grin Modbus Dictionary'
      default_value Modbus.default_file_path
      arg 'dictionary_file'
      flag [:d, :dictionary_file]

      desc 'Loop the command n times'
      default_value :forever
      arg 'loop', :optional
      flag [:l, :loop]

      desc 'Do not output to stdout'
      switch [:q, :quiet]

      desc 'Read a single or multiple adjacent registers from and address'
      arg_name 'register_address'
      command :read_register do |read_register|
        read_register.desc 'Number of registers to read starting at the Arg Address'
        read_register.default_value 1
        read_register.flag [:c, :count]

        read_register.arg 'address'
        read_register.action do |global_options, options, args|
          address = args[0].to_i
          count = args[1].to_i
          node = dict[address]
          puts modbus.range_address_header(address, count).join(",") unless quiet
          (0..loop).each do |i|
            puts modbus.read_raw_range(address, count).join(",") unless quiet
          end
        end
      end

      desc 'Logs interesting Phaserunner registers to stdout and file'
      long_desc %q(Logs interesting Phaserunner registers to stdout and a CSV file. File name in the form: phaserunner.#{Time.now.strftime('%Y-%m-%d_%H-%M-%S')}.csv)
      command :log do |log|
        log.action do |global_options, options, args|
          header = modbus.bulk_log_header
          data = modbus.bulk_log_data

          # Generate and output header line
          hdr = %Q(Timestamp,#{header.join(",")})
          puts hdr unless quiet
          phaserunnerOutFd.puts hdr

          (0..loop).each do |i| 
            str = %Q(#{Time.now.utc.round(10).iso8601(6)},#{data.join(",")})
            puts str unless quiet
            phaserunnerOutFd.puts str
            sleep 0.2
          end
        end
      end

      pre do |global, command, options, args|
        # Pre logic here
        # Return true to proceed; false to abort and not call the
        # chosen command
        # Use skips_pre before a command to skip this block
        # on that command only
        @modbus = Modbus.new(global)
        @dict = @modbus.dict
        # Handle that loop can be :forever or an Integer
        if global[:loop] == :forever
          @loop = Float::INFINITY
        else
          @loop = global[:loop].to_i
        end
        @quiet = global[:quiet]
        @phaserunnerOutFd = File.open("phaserunner.#{Time.now.strftime('%Y-%m-%d_%H-%M-%S')}.csv", 'w')
      end

      post do |global,command,options,args|
        # Post logic here
        # Use skips_post before a command to skip this
        # block on that command only
      end

      on_error do |exception|
        # Error logic here
        # return false to skip default error handling
        true
      end

      exit run(ARGV)
    end
  end
end
