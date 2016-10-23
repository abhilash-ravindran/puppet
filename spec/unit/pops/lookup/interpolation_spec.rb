#! /usr/bin/env ruby
require 'spec_helper'
require 'puppet'
require 'puppet/data_providers/hiera_config'
require 'puppet/data_providers/hiera_interpolate'

module Puppet::Pops
describe 'Puppet::Pops::Lookup::Interpolation' do
  include Lookup::SubLookup

  let(:interpolator) { Class.new { include Lookup::Interpolation }.new }
  let(:scope) { {} }
  let(:lookup_invocation) { Lookup::Invocation.new(scope, {}, {}, nil) }

  def expect_lookup(*keys)
    keys.each do |key|
      segments = split_key(key)
      root_key = segments.shift
      found = data[root_key]
      found = sub_lookup(key, lookup_invocation, segments, found) unless segments.empty?
      Lookup.expects(:lookup).with(key, nil, '', true, nil, lookup_invocation).returns(found)
    end
  end

  context 'when interpolating nested data' do
    let(:nested_hash) { {'a' => {'aa' => "%{alias('aaa')}"}} }

    let(:data) {
      {
        'aaa' => {'b' => {'bb' => "%{alias('bbb')}"}},
        'bbb' => ["%{alias('ccc')}"],
        'ccc' => 'text'
      }
    }

    it 'produces a nested hash with arrays from nested aliases with hashes and arrays' do
      expect_lookup('aaa', 'bbb', 'ccc')
      expect(interpolator.interpolate(nested_hash, lookup_invocation, true)).to eq('a' => {'aa' => {'b' => {'bb' => ['text']}}})
    end
  end

  context 'when there are empty interpolations %{} in data' do

    let(:empty_interpolation) { 'clown%{}shoe' }
    let(:empty_interpolation_as_escape) { 'clown%%{}{shoe}s' }
    let(:only_empty_interpolation) { '%{}' }
    let(:empty_namespace) { '%{::}' }
    let(:whitespace1) { '%{ :: }' }
    let(:whitespace2) { '%{   }' }

    it 'should produce an empty string for the interpolation' do
      expect(interpolator.interpolate(empty_interpolation, lookup_invocation, true)).to eq('clownshoe')
    end

    it 'the empty interpolation can be used as an escape mechanism' do
      expect(interpolator.interpolate(empty_interpolation_as_escape, lookup_invocation, true)).to eq('clown%{shoe}s')
    end

    it 'the value can consist of only an empty escape' do
      expect(interpolator.interpolate(only_empty_interpolation, lookup_invocation, true)).to eq('')
    end

    it 'the value can consist of an empty namespace %{::}' do
      expect(interpolator.interpolate(empty_namespace, lookup_invocation, true)).to eq('')
    end

    it 'the value can consist of whitespace %{ :: }' do
      expect(interpolator.interpolate(whitespace1, lookup_invocation, true)).to eq('')
    end

    it 'the value can consist of whitespace %{  }' do
      expect(interpolator.interpolate(whitespace2, lookup_invocation, true)).to eq('')
    end
  end

  context 'when there are quoted empty interpolations %{} in data' do

    let(:empty_interpolation) { 'clown%{""}shoe' }
    let(:empty_interpolation_as_escape) { 'clown%%{""}{shoe}s' }
    let(:only_empty_interpolation) { '%{""}' }
    let(:empty_namespace) { '%{"::"}' }
    let(:whitespace1) { '%{ "::" }' }
    let(:whitespace2) { '%{ ""  }' }

    it 'should produce an empty string for the interpolation' do
      expect(interpolator.interpolate(empty_interpolation, lookup_invocation, true)).to eq('clownshoe')
    end

    it 'the empty interpolation can be used as an escape mechanism' do
      expect(interpolator.interpolate(empty_interpolation_as_escape, lookup_invocation, true)).to eq('clown%{shoe}s')
    end

    it 'the value can consist of only an empty escape' do
      expect(interpolator.interpolate(only_empty_interpolation, lookup_invocation, true)).to eq('')
    end

    it 'the value can consist of an empty namespace %{"::"}' do
      expect(interpolator.interpolate(empty_namespace, lookup_invocation, true)).to eq('')
    end

    it 'the value can consist of whitespace %{ "::" }' do
      expect(interpolator.interpolate(whitespace1, lookup_invocation, true)).to eq('')
    end

    it 'the value can consist of whitespace %{ "" }' do
      expect(interpolator.interpolate(whitespace2, lookup_invocation, true)).to eq('')
    end
  end


  context 'when using dotted keys' do
    let(:data) {
      {
        'a.b' => '(lookup) a dot b',
        'a' => {
          'd' => '(lookup) a dot d is a hash entry',
          'd.x' => '(lookup) a dot d.x is a hash entry',
          'd.z' => {
            'g' => '(lookup) a dot d.z dot g is a hash entry'}
        },
        'a.x' => {
          'd' => '(lookup) a.x dot d is a hash entry',
          'd.x' => '(lookup) a.x dot d.x is a hash entry',
          'd.z' => {
            'g' => '(lookup) a.x dot d.z dot g is a hash entry'
          }
        },
        'x.1' => '(lookup) x dot 1',
        'key' => 'subkey'
      }
    }

    let(:scope) {
      {
        'a.b' => '(scope) a dot b',
        'a' => {
          'd' => '(scope) a dot d is a hash entry',
          'd.x' => '(scope) a dot d.x is a hash entry',
          'd.z' => {
            'g' => '(scope) a dot d.z dot g is a hash entry'}
        },
        'a.x' => {
          'd' => '(scope) a.x dot d is a hash entry',
          'd.x' => '(scope) a.x dot d.x is a hash entry',
          'd.z' => {
            'g' => '(scope) a.x dot d.z dot g is a hash entry'
          }
        },
        'x.1' => '(scope) x dot 1',
      }
    }

    it 'should find an entry using a quoted interpolation' do
      expect(interpolator.interpolate("a dot c: %{'a.b'}", lookup_invocation, true)).to eq('a dot c: (scope) a dot b')
    end

    it 'should find an entry using a quoted interpolation with method lookup' do
      expect_lookup("'a.b'")
      expect(interpolator.interpolate("a dot c: %{lookup(\"'a.b'\")}", lookup_invocation, true)).to eq('a dot c: (lookup) a dot b')
    end

    it 'should find an entry using a quoted interpolation with method alias' do
      expect_lookup("'a.b'")
      expect(interpolator.interpolate("%{alias(\"'a.b'\")}", lookup_invocation, true)).to eq('(lookup) a dot b')
    end

    it 'should use a dotted key to navigate into a structure when it is not quoted' do
      expect(interpolator.interpolate('a dot e: %{a.d}', lookup_invocation, true)).to eq('a dot e: (scope) a dot d is a hash entry')
    end

    it 'should report a key missing and replace with empty string when a dotted key is used to navigate into a structure and then not found' do
      expect(interpolator.interpolate('a dot n: %{a.n}', lookup_invocation, true)).to eq('a dot n: ')
    end

    it 'should use a dotted key to navigate into a structure when it is not quoted with method lookup' do
      expect_lookup('a.d')
      expect(interpolator.interpolate("a dot e: %{lookup('a.d')}", lookup_invocation, true)).to eq('a dot e: (lookup) a dot d is a hash entry')
    end

    it 'should use a mix of quoted and dotted keys to navigate into a structure containing dotted keys and quoted key is last' do
      expect(interpolator.interpolate("a dot ex: %{a.'d.x'}", lookup_invocation, true)).to eq('a dot ex: (scope) a dot d.x is a hash entry')
    end

    it 'should use a mix of quoted and dotted keys to navigate into a structure containing dotted keys and quoted key is last and method is lookup' do
      expect_lookup("a.'d.x'")
      expect(interpolator.interpolate("a dot ex: %{lookup(\"a.'d.x'\")}", lookup_invocation, true)).to eq('a dot ex: (lookup) a dot d.x is a hash entry')
    end

    it 'should use a mix of quoted and dotted keys to navigate into a structure containing dotted keys and quoted key is first' do
      expect(interpolator.interpolate("a dot xe: %{'a.x'.d}", lookup_invocation, true)).to eq('a dot xe: (scope) a.x dot d is a hash entry')
    end

    it 'should use a mix of quoted and dotted keys to navigate into a structure containing dotted keys and quoted key is first and method is lookup' do
      expect_lookup("'a.x'.d")
      expect(interpolator.interpolate("a dot xe: %{lookup(\"'a.x'.d\")}", lookup_invocation, true)).to eq('a dot xe: (lookup) a.x dot d is a hash entry')
    end

    it 'should use a mix of quoted and dotted keys to navigate into a structure containing dotted keys and quoted key is in the middle' do
      expect(interpolator.interpolate("a dot xm: %{a.'d.z'.g}", lookup_invocation, true)).to eq('a dot xm: (scope) a dot d.z dot g is a hash entry')
    end

    it 'should use a mix of quoted and dotted keys to navigate into a structure containing dotted keys and quoted key is in the middle and method is lookup' do
      expect_lookup("a.'d.z'.g")
      expect(interpolator.interpolate("a dot xm: %{lookup(\"a.'d.z'.g\")}", lookup_invocation, true)).to eq('a dot xm: (lookup) a dot d.z dot g is a hash entry')
    end

    it 'should use a mix of several quoted and dotted keys to navigate into a structure containing dotted keys and quoted key is in the middle' do
      expect(interpolator.interpolate("a dot xx: %{'a.x'.'d.z'.g}", lookup_invocation, true)).to eq('a dot xx: (scope) a.x dot d.z dot g is a hash entry')
    end

    it 'should use a mix of several quoted and dotted keys to navigate into a structure containing dotted keys and quoted key is in the middle and method is lookup' do
      expect_lookup("'a.x'.'d.z'.g")
      expect(interpolator.interpolate("a dot xx: %{lookup(\"'a.x'.'d.z'.g\")}", lookup_invocation, true)).to eq('a dot xx: (lookup) a.x dot d.z dot g is a hash entry')
    end

    it 'should find an entry using using a quoted interpolation on dotted key containing numbers' do
      expect(interpolator.interpolate("x dot 2: %{'x.1'}", lookup_invocation, true)).to eq('x dot 2: (scope) x dot 1')
    end

    it 'should find an entry using using a quoted interpolation on dotted key containing numbers using method lookup' do
      expect_lookup("'x.1'")
      expect(interpolator.interpolate("x dot 2: %{lookup(\"'x.1'\")}", lookup_invocation, true)).to eq('x dot 2: (lookup) x dot 1')
    end

    it 'should not find a subkey when the dotted key is quoted' do
      expect(interpolator.interpolate("a dot f: %{'a.d'}", lookup_invocation, true)).to eq('a dot f: ')
    end

    it 'should not find a subkey when the dotted key is quoted with method lookup' do
      expect_lookup("'a.d'")
      expect(interpolator.interpolate("a dot f: %{lookup(\"'a.d'\")}", lookup_invocation, true)).to eq('a dot f: ')
    end

    it 'should not find a subkey that is matched within a string' do
      expect{ expect_lookup('key.subkey') }.to raise_error(/Got String when a hash-like object was expected to access value using 'subkey' from key 'key.subkey'/)
    end
  end

  context 'when dealing with non alphanumeric characters' do
    let(:data) {
      {
        'a key with whitespace' => 'value for a ws key',
        'ws_key' => '%{alias("a key with whitespace")}',
        '\#@!&%|' => 'not happy',
        'angry' => '%{alias("\#@!&%|")}',
        '!$\%!' => {
          '\#@!&%|' => 'not happy at all'
        },
        'very_angry' => '%{alias("!$\%!.\#@!&%|")}',
        'a key with' => {
          'nested whitespace' => 'value for nested ws key',
          ' untrimmed whitespace ' => 'value for untrimmed ws key'
        }
      }
    }

    it 'allows keys with white space' do
      expect_lookup('ws_key', 'a key with whitespace')
      expect(interpolator.interpolate("%{lookup('ws_key')}", lookup_invocation, true)).to eq('value for a ws key')
    end

    it 'allows keys with non alphanumeric characters' do
      expect_lookup('angry', '\#@!&%|')
      expect(interpolator.interpolate("%{lookup('angry')}", lookup_invocation, true)).to eq('not happy')
    end

    it 'allows dotted keys with non alphanumeric characters' do
      expect_lookup('very_angry', '!$\%!.\#@!&%|')
      expect(interpolator.interpolate("%{lookup('very_angry')}", lookup_invocation, true)).to eq('not happy at all')
    end

    it 'allows dotted keys with nested white space' do
      expect_lookup('a key with.nested whitespace')
      expect(interpolator.interpolate("%{lookup('a key with.nested whitespace')}", lookup_invocation, true)).to eq('value for nested ws key')
    end

    it 'will trim each key element' do
      expect_lookup(' a key with . nested whitespace ')
      expect(interpolator.interpolate("%{lookup(' a key with . nested whitespace ')}", lookup_invocation, true)).to eq('value for nested ws key')
    end

    it 'will not trim quoted key element' do
      expect_lookup(' a key with ." untrimmed whitespace "')
      expect(interpolator.interpolate("%{lookup(' a key with .\" untrimmed whitespace \"')}", lookup_invocation, true)).to eq('value for untrimmed ws key')
    end

    it 'will not trim spaces outside of quoted key element' do
      expect_lookup(' a key with .  " untrimmed whitespace "  ')
      expect(interpolator.interpolate("%{lookup(' a key with .  \" untrimmed whitespace \"  ')}", lookup_invocation, true)).to eq('value for untrimmed ws key')
    end
  end

  context 'when dealing with bad keys' do
    it 'should produce an error when different quotes are used on either side' do
      expect { interpolator.interpolate("%{'the.key\"}", lookup_invocation, true)}.to raise_error("Syntax error in string: %{'the.key\"}")
    end

    it 'should produce an if there is only one quote' do
      expect { interpolator.interpolate("%{the.'key}", lookup_invocation, true)}.to raise_error("Syntax error in string: %{the.'key}")
    end

    it 'should produce an error for an empty segment' do
      expect { interpolator.interpolate('%{the..key}', lookup_invocation, true)}.to raise_error("Syntax error in string: %{the..key}")
    end

    it 'should produce an error for an empty quoted segment' do
      expect { interpolator.interpolate("%{the.''.key}", lookup_invocation, true)}.to raise_error("Syntax error in string: %{the.''.key}")
    end

    it 'should produce an error for an partly quoted segment' do
      expect { interpolator.interpolate("%{the.'pa'key}", lookup_invocation, true)}.to raise_error("Syntax error in string: %{the.'pa'key}")
    end

    it 'should produce an error when different quotes are used on either side in a method argument' do
      expect { interpolator.interpolate("%{lookup('the.key\")}", lookup_invocation, true)}.to raise_error("Syntax error in string: %{lookup('the.key\")}")
    end

    it 'should produce an error unless a known interpolation method is used' do
      expect { interpolator.interpolate("%{flubber(\"hello\")}", lookup_invocation, true)}.to raise_error("Unknown interpolation method 'flubber'")
    end
  end
end
end