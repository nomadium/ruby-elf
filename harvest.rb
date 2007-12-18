#!/usr/bin/env ruby
# Copyright © 2007, Diego "Flameeyes" Pettenò <flameeyes@gmail.com>
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

# This script is used to harvest the symbols defined in the shared
# objects of the whole system.

require 'getoptlong'
require 'set'
require 'pathname'
require 'sqlite3'
require 'elf'

opts = GetoptLong.new(
  ["--output",       "-o", GetoptLong::REQUIRED_ARGUMENT ],
  ["--pathscan",     "-p", GetoptLong::NO_ARGUMENT ],
  ["--suppressions", "-s", GetoptLong::REQUIRED_ARGUMENT ]
)

output_file = 'symbols-database.sqlite3'
suppression_file = 'suppressions'
scan_path = false

opts.each do |opt, arg|
  case opt
  when '--output'
    output_file = arg
  when '--suppressions'
    suppression_file = arg
  when '--pathscan'
    scan_path = true
  end
end

# Total suppressions are for directories to skip entirely
# Partial suppressions are the ones that apply only to a subset
# of symbols.
$total_suppressions = []
$partial_suppressions = []

File.open(suppression_file) do |file|
  file.each_line do |line|
    path, symbols = line.
      gsub(/#\s.*/, '').
      strip!.
      split(/\s+/, 2)

    next unless path
    
    if not symbols or symbols == ""
      $total_suppressions << Regexp.new(path)
    else
      $partial_suppressions << [Regexp.new(path), Regexp.new(symbols)]
    end
  end
end

ldso_paths = Set.new
ldso_paths.merge ENV['LD_LIBRARY_PATH'].split(":").set if ENV['LD_LIBRARY_PATH']

File.open("/etc/ld.so.conf") do |ldsoconf|
  ldso_paths.merge ldsoconf.readlines.
    delete_if { |l| l =~ /\s*#.*/ }.
    collect { |l| l.strip }.
    uniq
end

so_files = Set.new

# Extend Pathname with a so_files method
class Pathname
  def so_files(recursive = true)
    res = Set.new
    each_entry do |entry|
      begin
        next if entry.to_s =~ /\.\.?$/
        entry = (self + entry).realpath

        skip = false

        $total_suppressions.each do |supp|
          if entry.to_s =~ supp
            skip = true
            break
          end
        end

        next if skip

        if entry.directory?
          res.merge entry.so_files if recursive
          next
        elsif entry.to_s =~ /\.so[\.0-9]*$/
          res.add entry.to_s
        end
      rescue Errno::EACCES, Errno::ENOENT
        next
      end
    end

    return res
  end
end

ldso_paths.each do |path|
  begin
    so_files.merge Pathname.new(path.strip).so_files
  rescue Errno::ENOENT
    next
  end
end

if scan_path and ENV['PATH']
  ENV['PATH'].split(":").each do |path|
    so_files.merge Pathname.new(path).so_files(false)
  end
end

db = SQLite3::Database.new output_file
db.execute("CREATE TABLE objects ( id INTEGER PRIMARY KEY, path, abi, soname )")
db.execute("CREATE TABLE symbols ( object INTEGER, symbol )")

val = 0

so_files.each do |so|
  local_suppressions = $partial_suppressions.dup.delete_if { |s| not so.to_s =~ s[0] }

  begin
    Elf::File.open(so) do |elf|
      next unless elf.sections['.dynsym'] and elf.sections['.dynstr']

      abi = "#{elf.elf_class} #{elf.abi} #{elf.machine}"
      soname = ""
      needed_objects = []

      if elf.sections['.dynamic']
        elf.sections['.dynamic'].entries.each do |entry|
          case entry[:type]
          when Elf::Dynamic::Type::Needed
            needed_objects << elf.sections['.dynstr'][entry[:attribute]]
          when Elf::Dynamic::Type::SoName
            soname = elf.sections['.dynstr'][entry[:attribute]]
          end
        end
      end

      val += 1

      db.execute("INSERT INTO objects(id, path, abi, soname) VALUES(#{val}, '#{so}', '#{elf.elf_class} #{elf.abi} #{elf.machine}', '#{soname}')")

      elf.sections['.dynsym'].symbols.each do |sym|
        begin
          next if sym.idx == 0 or
            sym.bind != Elf::Symbol::Binding::Global or
            sym.section == nil or
            sym.value == 0 or
            sym.section.is_a? Integer or
            sym.section.name == '.init'

          skip = false
          
          local_suppressions.each do |supp|
            if sym.name =~ supp[1]
              skip = true
              break
            end
          end

          next if skip

          db.execute("INSERT INTO symbols VALUES('#{val}', '#{sym.name}@@#{sym.version}')")
        rescue Exception
          $stderr.puts "Mangling symbol #{sym.name}"
          raise
        end
      end
    end
  rescue Elf::File::NotAnELF
    next
  rescue Exception
    $stderr.puts "Checking #{so}"
    raise
  end
end