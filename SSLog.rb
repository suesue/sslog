#!/usr/bin/ruby
# -*- coding: utf-8 -*-

require 'time'

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
		self
	end

	def to_hash
		{ :timestamp => @timestamp, :level => @level, :tag => @tag, :message => @message, :line => @line }
	end

	def to_s
		"Log Entry { timestamp = #{@timestamp}, level = #{@level}, tag = #{@tag}, message = #{@message}, line = #{@line} }"
	end

end


class Thread

	def <<( entry )
		@entries ||= []
		@entries << entry
		self
	end

	def fix
		self
	end

end


class ThreadFilter

	def accept?( entry )
		entry ? true: false
	end

	def new_thread
#puts "#{self.class.name}#new_thread: called"
		Thread.new
	end

end


class ParserContext
	attr_reader :last
	attr_reader :current
	attr_accessor :input


	def read
		raise unless @input
		raise unless block_given?
		reset
		@input.read do |line|
			yield line
		end
		self
	end

	def reset
		@last = nil
		@current = nil
		@values = nil
		self
	end

	def discard
		@last = nil
		@current = nil
		self
	end

	def stay( entry = nil )
		# do nothing
		self
	end

	def append( line )
		if @last then
			@last.append_line line
		end
		self
	end

	def forward( entry = @current )
		if @last then
			push
		end
		@last = entry
		@current = nil
		self
	end

	def push( entry = @last )
		self << entry if entry
	end

	def <<( entry )
		self
	end

	def new_entry
		entry = Entry.new
		@current = entry
		entry
	end

	def commit
		self
	end

	def []( key )
		@values ? @values[ key ]: nil
	end

	def []=( key, value )
		@values ||= {}
		old = @values[ key ]
		@values[ key ] = value
		old
	end

end


class MultiParserContext < ParserContext

	def +( context )
		@list ||= []
		@list << context
		self
	end

	def reset
		@list.each do |context|
			context.reset
		end if @list
		self
	end

	def <<( entry )
		return self unless @list
		@list.each do |context|
			context << entry
		end
		self
	end

	def commit
		@list.each do |context|
			context.commit
		end if @list
		self
	end

end


class Parser

	def parse( context, &block )
		context.read do |line|
			entry = read_next( context, line )
			if entry == line then
				context.append entry
			elsif entry.kind_of?( Entry ) then
				context.forward entry
			elsif entry.nil? then
				context.discard
			else
				context.stay entry
			end
		end
		context.forward
		context.commit
	end

	def read_next( context, line )
		context.new_entry.read( line )
	end

end


class Store < ParserContext
	require 'sqlite3'


	def initialize( path = "log.db" )
		raise unless path
		@path = path
		@limit = 1000
	end

	def reset
		super

		@counter = 0
		@db = nil
		@db = SQLite3::Database.new( @path )

		create

		@in_transaction = false
	end

	def <<( entry )
		unless @in_transaction then
			@db.transaction
			@in_transaction = true
		end

		insert entry

		@counter += 1
		if @counter >= @limit then
			@db.commit
			@counter = 0
			@in_transaction = false
		end

		self
	end

	def create
		@db.execute <<SQL
CREATE TABLE IF NOT EXISTS log (
line_no,
line,
at,
tag,
level,
message
);
SQL
	end

	def insert( entry )
		@db.execute "INSERT INTO log (line_no, line, at, tag, level, message) VALUES (?, ?, ?, ?, ?, ?)",
			entry.line.number,
			entry.line.text,
			entry.timestamp ? entry.timestamp.strftime("%Y-%m-%d %H:%M:%S"): nil,
			entry.tag,
			entry.level ? entry.level.to_s: nil,
			entry.message

		self
	end

	def commit
		if @counter > 0 then
			@db.commit
			@counter = 0
		end
		@db.close
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

			if arg =~ /\A---+/ then
				raise
			elsif arg =~ /\A--(.+)\z/ then
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
			elsif arg =~ /\A-(.+)\z/ then
				raise
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
