#!/usr/bin/ruby
# -*- coding: utf-8 -*-

require "#{File.dirname(__FILE__)}/SSLog"

module SS
module Java

class StackTrace

	def initialize
		@lines = []
	end

	def at_top( line )
		@lines.insert 0, line
	end

	def <<( line )
		@lines << line
	end

	def empty?
		@lines.empty?
	end

	def print
		puts "================================"
		@lines.each do |line|
			puts "#{line.number}|#{line.text.chomp}"
		end
	end

	def self.parse( context, &block )
		st = StackTrace.new
		temp = nil
		context.read do |line|
			l = line.text.chomp
			case l
			when /\s*Caused\s+by:\s+.*\z/ then
				st << line
				temp = nil
			when /\s+at\s+\S+\(.+\)\z/ then
				if temp then
					st.at_top temp
					temp = nil
				end
				st << line
			when /\s+\.\.\.\s+\d+\s+more\z/ then
				st << line
				temp = nil
			else
				unless st.empty? then
					st.print
					st = StackTrace.new
				end
				temp = line
			end
		end
		unless st.empty? then
			st.print
		end
	end

	def self.main( args )
		context = SS::Log::ParserContext.new
		context.input = SS::Text::Stream.new( STDIN )
		StackTrace.parse context
	end

end

end
end


if __FILE__ == $0 then
	SS::Java::StackTrace::main ARGV
end
