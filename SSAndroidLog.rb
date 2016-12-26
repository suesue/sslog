#!/usr/bin/ruby
# -*- coding: utf-8 -*-

require "#{File.dirname(__FILE__)}/SSLog"


module SS
module Android

class LogBlockMark

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


class LogEntry < SS::Log::Entry
	attr_reader :entity
	attr_reader :mark


	def initialize( mark = nil, org = nil )
		if org then
			super org
			@entity = org.entity
			@mark = org.mark
		end
		@mark = mark if mark
	end

	def read( line )
		case line.text
		when /\A(\d+-\d+ \d+:\d+:\d+)\.\d+ (\S)\/(.+)\(\s*(\d+)\): (.*)[\r\n]*\z/ then
			@timestamp = DateTime.strptime( $1, "%m-%d %H:%M:%S" )
			@level = to_level( $2 )
			@tag = $3
			pid = $4.to_i
			@entity = Entity.new( pid, nil, nil, nil )
			@message = $5
		when /\A(\d+-\d+ \d+:\d+:\d+)\.\d+ (\d+)-(\d+)\/(\S+) (\S)\/([^:]+): (.*)[\r\n]*\z/ then
			@timestamp = DateTime.strptime( $1, "%m-%d %H:%M:%S" )
			@level = to_level( $5 )
			@tag = $6
			pid = $2.to_i
			@message = $7
			package_name = $4
			@entity = Entity.new( pid, package_name, nil, nil )
		else
			#raise "!!! ##{line.number}: #{line.text}"
#puts line.text
			return line
		end

		@line = line

		if @message =~ /\AStart proc (\d+):(.*)/ then
			spid = $1.to_i
			detail = $2
			package_name = nil
			entity_name = nil
			entity_type = nil
			case detail
			when /\A([^\/]+)\/[^\/]+ for (activity|service|broadcast) ([^\/]+)\/\.([^\/]+)/ then
				package_name = $1
				entity_type = $2
				entity_name = "#{$3}.#{$4}"
#puts "package name = #{package_name}, entity name = #{entity_name}"
			when /\A([^\/]+)\/[^\/]+ for (activity|service|broadcast) ([^\/]+)\/([^\/]+)/ then
				package_name = $1
				entity_type = $2
				entity_name = $4
#puts "package name = #{package_name}, entity name = #{entity_name}"
			when /\A([^\/]+)\/[^\/]+ for/ then
				#puts "start proc ?"
#puts "#{@message}; package name = #{package_name}, entity name = #{entity_name}"
			else
				#puts "start proc ???"
#puts "#{@message}"
			end
			entity = Entity.new( spid, package_name, entity_name, entity_type )
			EntityStartLogEntry.new( entity, self )
		else
			self
		end
#puts self.to_s
	end

	def to_level( char )
		case char
		when 'V' then
			SS::Log::Level.new( :VERBOSE )
		when 'D' then
			SS::Log::Level.new( :DEBUG )
		when 'I' then
			SS::Log::Level.new( :INFO )
		when 'W' then
			SS::Log::Level.new( :WARNING )
		when 'E' then
			SS::Log::Level.new( :ERROR )
		when 'F' then
			SS::Log::Level.new( :FATAL )
		else
			raise "Unknown log level: #{char}"
		end
	end

	def to_hash
		hash = super
		hash[ :mark ] = @mark
		hash[ :entity ] = @entity
		hash
	end

	def to_s
		"Android Log Entry { timestamp = #{@timestamp}, level = #{@level}, mark = #{@mark}, tag = #{@tag}, entity = #{@entity}, message = #{@message}, line = #{@line} }"
	end

end


class Entity
	attr_reader :pid
	attr_reader :package_name
	attr_reader :name
	attr_reader :type


	def initialize( pid, package_name, name, type )
		@pid = pid
		@package_name = package_name
		@name = name
		@type = type
	end

	def to_s
		"Android Entity { PID = #{@pid}, package name = #{@package_name}, name = #{@name}, type = #{@type} }"
	end

end


class EntityStartLogEntry < LogEntry
	attr_reader :target_entity


	def initialize( entity, org = nil )
		super nil, org
		@target_entity = entity
	end

	def to_s
		"Android Entity Start Log Entry { target entity = #{@target_entity}, timestamp = #{@timestamp}, level = #{@level}, mark = #{@mark}, tag = #{@tag}, entity = #{@entity}, message = #{@message}, line = #{@line} }"
	end

end


class LogParser < SS::Log::Parser

	def read_next( context, line )
		l = line.text.chomp
		if l.empty? then
			nil
		elsif l =~ /\A\*.*\*/ then
			nil
		elsif l =~ /\A--------- beginning of (.+)$/ then
			mark = LogBlockMark.new( $1.to_sym )
			if context.last then
				context.push
				context.discard
			end
			context[ :mark ] = mark
			mark
		else
			LogEntry.new( context[ :mark ] ).read( line )
		end
	end

end


class ApkLogContext < SS::Log::ParserContext
	attr_reader :target_packages
	attr_reader :system_process


	def initialize
		@target_packages = []
		@target_package_regexps = {}
		@messages_before_start = {}
	end

	def reset
		super
		@entities = {}
		@temp = []
		@last_pid = nil
		@last_block_number = 1
		@html = ""
	end

	def <<( entry )
		if entry.nil? then
		elsif entry.kind_of?( EntityStartLogEntry ) then
			# entity start
			package_name = entry.target_entity.package_name
			unless @system_process then
				name = entry.entity.package_name ? entry.entity.package_name: 'system_process'
				@system_process = Entity.new( entry.entity.pid, name, nil, nil )
			end
#puts "A-0; ##{entry.line.number}; #{package_name}<br>"
			if @target_packages.include?( package_name ) then
#puts "A-1; ##{entry.line.number}; #{package_name}"
				if @entities[ package_name ] then
					# duplicated ... restart ?
				end
#puts "A-2; ##{entry.line.number}; #{package_name}"
				@entities[ package_name ] = entry.target_entity
				if @messages_before_start[ package_name ] then
					@temp = @messages_before_start[ package_name ]
					@messages_before_start[ package_name ] = nil
					write
				end
				if @last_pid and @last_pid != entry.target_entity.pid then
#puts "A-3; ##{entry.line.number}"
					write
				end
				@last_pid = entry.target_entity.pid
				@temp << entry
			end
		else
#puts "B-0; ##{entry.line.number}"
			entity = nil
			@entities.each_value do |s|
				if entry.entity.pid == s.pid or entry.entity.package_name == s.package_name then
					entity = entry.entity
					break
				end
			end
			unless entity then
				@target_packages.each do |p|
					if @target_package_regexps.nil? or @target_package_regexps[ p ].nil? then
						@target_package_regexps ||= {}
						@target_package_regexps[ p ] ||= []
						@target_package_regexps[ p ] << Regexp.new( "[^a-zA-Z_0-9]+#{p}[^a-zA-Z_0-9]+" )
						@target_package_regexps[ p ] << Regexp.new( "^#{p}[^a-zA-Z_0-9]+" )
						@target_package_regexps[ p ] << Regexp.new( "[^a-zA-Z_0-9]+#{p}$" )
					end
					@target_package_regexps[ p ].each do |regexp|
						if entry.message =~ regexp then
#puts "#{entry.line.text}"
							@messages_before_start[ p ] ||= []
							@messages_before_start[ p ] << entry
							break
						end
					end
				end
			end
#			unless entity then
#puts "B-1; ##{entry.line.number}"
#				@target_packages.each do |p|
#					if entry.entity.package_name == p then
#						entity = entry.entity
#						break
#					end
#				end
#			end
			if entity then
#puts "B-2 #{entry.line.number}: entity = #{entity}"
				if @last_pid and @last_pid != entity.pid then
#puts "B-4 #{entry.line.number}"
					write
				end
				@last_pid = entity.pid
				@temp << entry
			end
		end
		self
	end

	def write
		@html += "<tr><td align=\"right\">#{@last_block_number}</td>"
#f = false
		@target_packages.each do |name|
			if @entities[ name ] and @entities[ name ].pid == @last_pid then
				@html += '<td><pre>'
				@temp.each do |t|
					@html += t.line.text.gsub( /\r\n\r\n/, "\r\n" ).gsub( /\r\r/, "\r" ).gsub( /\n\n/, "\n" ).gsub( /</, "&lt;" ).gsub( />/, "&gt;" )
				end
				@html += '</pre></td>'
#f = true
			else
				@html += '<td></td>'
			end
		end
#puts "<!--#{@temp}-->" unless f
		@html += '</tr>'
		@last_block_number += 1
		@temp = []
	end

	def commit
		write unless @temp.empty?

		print_head
		puts @html
		print_tail
	end

	def print_head
		puts <<HTML
<!DOCTYPE html>
<html>

<head>
	<meta charset="utf-8">
	<title>Android Log</title>
</head>

<body>
<table border="1">
<thead>
<tr>
	<td>#</td>
HTML

		@target_packages.each do |name|
			if @entities[ name ] and @entities[ name ].pid then
				puts "<td>#{name}<br>(#{@entities[name].pid})</td>"
			elsif @system_process and @system_process.package_name == name then
				puts "<td>#{name}<br>(#{@system_process.pid})</td>"
			else
				puts "<td>#{name}<br>(?)</td>"
			end
		end
		puts <<HTML
</tr>
</thead>
<tbody>
HTML
	end

	def print_tail
		puts <<HTML
</tbody>
</table>
</body>

</html>
HTML
	end

end


class Store < SS::Log::Store

	def initialize( path = "android_log.db" )
		super path
	end

	def create
		@db.execute <<SQL
CREATE TABLE IF NOT EXISTS log (
line_no,
line,
at,
entity_pid,
entity_package_name,
entity_name,
entity_type,
mark,
tag,
level,
message
);
SQL

		@db.execute <<SQL
CREATE TABLE IF NOT EXISTS entity (
pid,
package_name,
name,
type
);
SQL
	end

	def insert( entry )
		if entry.kind_of?( EntityStartLogEntry ) then
			@db.execute "INSERT INTO entity (pid, package_name, name, type) VALUES (?, ?, ?, ?)",
				entry.target_entity.pid,
				entry.target_entity.package_name,
				entry.target_entity.name,
				entry.target_entity.type
			@counter += 1
		end

		@db.execute "INSERT INTO log (line_no, line, at, entity_pid, entity_package_name, entity_name, entity_type, mark, tag, level, message) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
			entry.line.number,
			entry.line.text,
			entry.timestamp ? entry.timestamp.strftime("%Y-%m-%d %H:%M:%S"): nil,
			entry.entity ? entry.entity.pid: nil,
			entry.entity ? entry.entity.package_name: nil,
			entry.entity ? entry.entity.name: nil,
			entry.entity ? entry.entity.type: nil,
			entry.mark ? entry.mark.to_s: nil,
			entry.tag,
			entry.level ? entry.level.to_s: nil,
			entry.message

		self
	end

end


class LogDump
	require 'sqlite3'


	def initialize( path = nil )
		path ||= "android_log.db"
		@db = SQLite3::Database.new( path )
	end

	def by_pid( pid, out = nil )
		out ||= STDOUT
		sql = "SELECT line FROM log WHERE entity_pid = #{pid} ORDER BY line_no"
		@db.execute sql do |row|
			out.puts row[ 0 ]
		end
	end

end

end
end


def main( args )
	include SS::Android

	option = SS::CommandLine::Option.new( args ).parse
#p option

#	format = option.of( 'format' )

	dump = option.of( 'dump' )
	if dump then
		pid = option.of( 'pid' )
		LogDump.new.by_pid pid[ 0 ]
		return
	end

	context = nil
	output = option.of( 'output' )
	if output then
		context = SS::Log::MultiParserContext.new
		output.each do |o|
			case o
			when "html"
				c = ApkLogContext.new
				package_names = option.of( 'package-names' )
				if package_names then
					package_names.each do |name|
						c.target_packages << name
					end
					c.target_packages << 'system_process'
				end
				context + c
			when "db"
				c = Store.new
				context + c
			else
				raise
			end
		end
	else
		context = Store.new
	end

	input = option.of( 'input' )
	connect = option.of( 'connect' )
	if input then
		input.each do |s|
			context.input = SS::Text::File.new( s )
			LogParser.new.parse context
		end
	elsif connect then
	else
		context.input = SS::Text::Stream.new( STDIN )
		LogParser.new.parse context
	end
end


if __FILE__ == $0 then
	main ARGV
end


#
# SELECT DISTINCT tag FROM log ORDER BY tag
# SELECT tag, message FROM log WHERE EXISTS (SELECT '' FROM entity WHERE entity_pid = pid AND package_name = 'x.x.x') ORDER BY at
# SELECT message FROM log WHERE EXISTS (SELECT '' FROM entity WHERE entity_pid = pid AND package_name = 'x.x.x') ORDER BY at
#
