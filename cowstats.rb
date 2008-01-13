#!/usr/bin/env ruby
# Copyright © 2008, Diego "Flameeyes" Pettenò <flameeyes@gmail.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this generator; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

# simple script to check for variables in copy-on-write sections

require 'elf'
require 'getoptlong'

opts = GetoptLong.new(
  # Only show statistics for the various files
  ["--statistics", "-s", GetoptLong::NO_ARGUMENT],
  # Show the total size of COW pages
  ["--total", "-t", GetoptLong::NO_ARGUMENT]
)

unless ARGV.length > 0
  $stderr.puts "Please provide at least a file to check."
end

stats_only = false
show_total = false

opts.each do |opt, arg|
  case opt
  when '--statistics'
    stats_only = true
  when '--total'
    show_total = true
  end
end

files_info = {}
data_total = 0
bss_total = 0
rel_total = 0

ARGV.each do |file|
  begin
    Elf::File.open(file) do |elf|
      if elf.type != Elf::File::Type::Rel
        $stderr.puts "cowstats.rb: #{file}: not an object file"
        next
      end

      files_info[file] = {}
      
      data_vars = []
      bss_vars = []
      rel_vars = []
      
      elf.sections['.symtab'].symbols.each do |symbol|
        # Ignore undefined, absolute and common symbols.
        next unless symbol.section.is_a? Elf::Section
        # When the symbol name is empty, it refers to the
        # section itself.
        next if symbol.name == ""
        
        case symbol.section.name
        when /\.data(\.local)?$/
          data_vars << symbol
        when /\.bss$/
          bss_vars << symbol
        when /\.data\.rel(\.local)?$/
          rel_vars << symbol
        end
      end
      
      files_info[file]["data_vars"] = data_vars
      files_info[file]["bss_vars"] = bss_vars
      files_info[file]["rel_vars"] = rel_vars
    end
  rescue Errno::ENOENT
    $stderr.puts "cowstats.rb: #{file}: no such file"
  rescue Elf::File::NotAnELF
    $stderr.puts "cowstats.rb: #{file}: not a valid ELF file."
  end
end

if not stats_only
  files_info.each_pair do |file, info|
    next unless (info["data_vars"] + info["bss_vars"] + info["rel_vars"] ).length > 0
    puts "Processing file #{file}"
    
    data_size = 0
    bss_size = 0
    rel_size = 0
    
    if info["data_vars"].length > 0
      puts "  The following variables are writable (Copy-On-Write):"
      info["data_vars"].each do |sym|
        puts "    #{sym} (size: #{sym.size})"
        data_size += sym.size
      end
    end
    data_total += data_size

    if info["bss_vars"].length > 0
      puts "  The following variables aren't initialised (Copy-On-Write):"
      info["bss_vars"].each do |sym|
        puts "    #{sym} (size: #{sym.size})"
        bss_size += sym.size
      end
    end
    bss_total += bss_size

    if info["rel_vars"].length > 0
      puts "  The following variables need runtime relocation (Copy-On-Write):"
      info["rel_vars"].each do |sym|
        puts "    #{sym} (size: #{sym.size})"
        rel_size += sym.size
      end
    end
    rel_total += rel_size

    puts "  Total writable variables size: #{data_size}" unless data_size == 0
    puts "  Total non-initialised variables size: #{bss_size}" unless bss_size == 0
    puts "  Total variables needing runtime relocation size: #{rel_size}" unless rel_size == 0

  end
else
  maxlen = "File name".length
  max_data_len = ".data size".length
  max_bss_len = ".bss size".length
  max_rel_len = ".data.rel.* size".length

  output_info = []

  files_info.each_pair do |file, info|
    next unless (info["data_vars"] + info["bss_vars"] + info["rel_vars"] ).length > 0
    maxlen = file.length if maxlen < file.length

    data_size = 0
    info["data_vars"].each { |sym| data_size += sym.size }
    data_total += data_size
    max_data_len = data_size.to_s.length if max_data_len < data_size.to_s.length

    bss_size = 0
    info["bss_vars"].each { |sym| bss_size += sym.size }
    bss_total += bss_size
    max_bss_len = bss_size.to_s.length if max_bss_len < bss_size.to_s.length

    rel_size = 0
    info["rel_vars"].each { |sym| rel_size += sym.size }
    rel_total += rel_size
    max_rel_len = rel_size.to_s.length if max_rel_len < rel_size.to_s.length

    output_info << [file, data_size, bss_size, rel_size]
  end

  puts "#{'File name'.ljust maxlen} | #{'.data size'.ljust max_data_len} | #{'.bss size'.ljust max_data_len} | #{'.data.rel.* size'.ljust max_data_len}"
  output_info.each do |info|
    puts "#{info[0].ljust maxlen}   #{info[1].to_s.rjust max_data_len}   #{info[2].to_s.rjust max_data_len}   #{info[3].to_s.rjust max_data_len}"
  end
end

if show_total
  puts "Totals:"
  puts "    #{data_total} bytes of writable variables."
  puts "    #{bss_total} bytes of non-initialised variables."
  puts "    #{rel_total} bytes of variables needing runtime relocation."
  puts "  Total #{data_total+bss_total+rel_total} bytes of variables in copy-on-write sections"
end
