# Copyright 2008, Diego "Flameeyes" Pettenò <flameeyes@gmail.com>
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

require 'test/unit'
require 'pathname'
require 'elf'

# Test for GNU versioning support
#
# GNU binutils and glibc support a versioning feature that allows to
# create symbols with multiple versions; this test ensures that
# ruby-elf can read the versioning information correctly.
class TC_Versioning < Test::Unit::TestCase
  TestDir = Pathname.new(__FILE__).dirname + "binaries"

  def setup
    @elf = Elf::File.new(TestDir + "linux_amd64_versioning.so")
  end

  def teardown
    @elf.close
  end

  def test_sections_presence
    [".gnu.version", ".gnu.version_d", ".gnu.version_r"].each do |sect|
      assert(@elf[sect],
             "Missing section #{sect}")
    end
  end

  def test_sections_types
    assert(@elf[".gnu.version"].type == Elf::Section::Type::GNU::VerSym,
          "Section .gnu.version of wrong type (#{@elf[".gnu.version"].type})")
    assert(@elf[".gnu.version_d"].type == Elf::Section::Type::GNU::VerDef,
          "Section .gnu.version_d of wrong type (#{@elf[".gnu.version_d"].type})")
    assert(@elf[".gnu.version_r"].type == Elf::Section::Type::GNU::VerNeed,
          "Section .gnu.version_r of wrong type (#{@elf[".gnu.version_r"].type})")
  end

  def test_sections_classes
    assert(@elf[".gnu.version"].class == Elf::GNU::SymbolVersionTable,
           "Section .gnu.version of wrong class (#{@elf[".gnu.version"].class})")
    assert(@elf[".gnu.version_d"].class == Elf::GNU::SymbolVersionDef,
           "Section .gnu.version_d of wrong class (#{@elf[".gnu.version_d"].class})")
    assert(@elf[".gnu.version_r"].class == Elf::GNU::SymbolVersionNeed,
           "Section .gnu.version_r of wrong class (#{@elf[".gnu.version_r"].class})")
  end

  def test__gnu_version
    assert(@elf[".gnu.version"].count == @elf[".dynsym"].symbols.size,
           "Wrong version information count (#{@elf[".gnu.version"].count}, expected #{@elf[".dynsym"].symbols.size})")
  end

  def test__gnu_version_d
    section = @elf[".gnu.version_d"]
    
    # We always have a "latent" version with the soname of the
    # library, which is the one used by --default-symver option of GNU
    # ld.
    assert(section.count == 2,
           "Wrong amount of versions defined (#{section.count}, expected 2)")

    assert(section[1][:names].size == 1,
           "First version has more than one expected name (#{section[1][:names].size})")
    assert(section[1][:names][0] == Pathname(@elf.path).basename.to_s,
           "First version name does not coincide with the filename (#{section[1][:names][0]})")
    assert(section[1][:flags] & Elf::GNU::SymbolVersionDef::FlagBase == Elf::GNU::SymbolVersionDef::FlagBase,
           "First version does not report as base version (#{section[1][:flags]})")

    assert(section[2][:names].size == 1,
           "Second version has more than one expected name (#{section[2][:names].size})")
    assert(section[2][:names][0] == "VERSION1",
           "Second version name is not what is expected (#{section[2][:names][0]})")
  end

  def test__gnu_version_r
    section = @elf[".gnu.version_r"]

    
    assert(section.count == 1,
           "Wrong amount of needed versions (#{section.count}, expected 1)")

    # The indexes are incremental between defined and needed
    assert(section[3],
           "Version with index 3 not found.")

    assert(section[3][:name] == "GLIBC_2.2.5",
           "The needed version is not the right name (#{section[3][:name]})")
  end

  def test_symbols
    first_asymbol_seen = false
    @elf[".dynsym"].symbols.each do |sym|
      case sym.name
      when "tolower"
        assert(sym.version == "GLIBC_2.2.5",
               "Imported \"tolower\" symbol is not reporting the expected version (#{sym.version})")
      when "asymbol"
        unless first_asymbol_seen
          assert(sym.version == "VERSION1",
                 "Defined symbol \"asymbol\" is not reporting the expected version (#{sym.version})")
          first_asymbol_seen = true
        else
          assert(sym.version == nil,
                 "Defined symbol \"asymbol\" is reporting an unexpected version (#{sym.version})")
        end
      end
    end
  end

end

