#!/usr/bin/ruby
# -*- coding: utf-8 -*-

module SS
module Text

class Line
	attr_reader :input
	attr_reader :number
	attr_reader :text


	def initialize( input, number, text )
		raise unless input
		raise unless text
		@input = input
		@number = number
		@text = text
	end

	def +( value )
		@text += value.text
		self
	end

	def to_s
		"SS Text Line { input = #{@input}, number = #{@number}, text = #{@text} }"
	end

end


class Input

	def read_all( stream = nil )
		stream ||= STDIN
		lines = [] unless block_given?
		number = 1
		while line = stream.gets do
			tline = Line.new( self, number, line )
			if block_given? then
				yield tline
			else
				lines << tline
			end
			number += 1
		end
		lines
	end

end


class Stream < Input
	attr_reader :source


	def initialize( source )
		raise unless source
		@source = source
	end

	def read( &block )
		return read_all( @source, &block )
	end

	def to_s
		"SS Text Stream { source = #{@source} }"
	end

end


class File < Input
	attr_reader :path


	def initialize( path )
		raise unless path
		@path = path
	end

	def read( &block )
		open( @path, 'r' ) do |file|
			return read_all( file, &block )
		end
	end

	def to_s
		"SS Text File { path = #{@path} }"
	end

end

end


module Log

class Level

	def initialize( symbol )
		raise unless symbol
		@symbol = symbol
	end

	def to_sym
		@symbol
	end

	def to_s
		@symbol.to_s
	end

end


class Entry
	attr_reader :timestamp
	attr_reader :tag
	attr_reader :level
	attr_reader :message
	attr_reader :line


	def initialize( org = nil )
		if org then
			@timestamp = org.timestamp
			@tag = org.tag
			@level = org.level
			@message = org.message
			@line = org.line
		end
	end

	def timestamp_from_line( line )
		nil
	end

	def tag_from_line( line )
		nil
	end

	def level_from_line( line )
		nil
	end

	def message_from_line( line )
		nil
	end

	def read( line )
		@timestamp = timestamp_from_line( line )
		@level = tag_from_line( line )
		@tag = level_from_line( line )
		@message = message_from_line( line )
		@line = line
#puts self.to_s
		self
	end

	def append_line( line )
		@line + line
		update
	end

	def update
	end

	def to_s
		"Log Entry { timestamp = #{@timestamp}, level = #{@level}, tag = #{@tag}, message = #{@message}, line = #{@line} }"
	end

end


class Thread

	def accept?( entry )
		return false unless entry
	end

	def <<( entry )
		@entries ||= []
		@entries << entry
	end

end


class ParserContext
	attr_accessor :last_entry
	attr_accessor :input


	def reset
		@last_entry = nil
		@values = nil
	end

	def new_entry
		Entry.new
	end

	def <<( entry )
		self
	end

	def []( key )
		@values ? @values[ key ]: nil
	end

	def []=( key, value )
		@values ||= {}
		@values[ key ] = value
	end

	def commit
	end

end


class Parser

	def parse( context, &block )
		raise unless context.input
		context.reset
		context.input.read do |line|
			entry = read_next( context, line )
			if entry == line then
				next unless context.last_entry # ignore
				context.last_entry.append_line line
			elsif entry.kind_of?( Entry ) then
				if context.last_entry then
					context << context.last_entry
				end
				context.last_entry = entry
			elsif entry.nil? then
				context.last_entry = nil
			else
				; # do nothing
			end
		end
		if context.last_entry then
			context << context.last_entry
			context.last_entry = nil
		end
		context.commit
	end

	def read_next( context, line )
		context.new_entry.read( line )
	end

end

end


module CommandLine

class Option
	attr_reader :names
	attr_reader :unnamed


	def initialize( args, names = nil )
		raise unless args
		@args = args
		@names = names
	end

	def parse
		unnamed = nil
		name = nil
		values = nil
		named = {}
		@args.each do |arg|
			if unnamed then
				unnamed << arg
				next
			end

			if arg =~ /\A--(.+)\z/ then
				if name and values.nil? then
					named[ name ] = []
				end
				name = $1.to_sym
				values = named[ name ]
				next
			elsif arg =~ /\A--\z/ then
				unnamed = []
				name = nil
				values = nil
				next
			elsif name then
				unless values then
					values = []
					named[ name ] = values
				end
				values << arg
				next
			else
				unnamed = []
				name = nil
				values = nil
				next
			end
		end
		@unnamed = unnamed ? unnamed: []
		@named = named
		self
	end

	def of( name, index = nil )
		if name then
			values = @named[ name.to_sym ]
			if index then
				values[ index ]
			else
				values
			end
		else
			nil
		end
	end

	def []( index )
		@unnamed[ index ]
	end

	def size
		@unnamed.length
	end

end

end
end
