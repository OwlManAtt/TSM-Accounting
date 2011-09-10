#!/usr/bin/ruby
$:.unshift("#{File.expand_path(File.dirname(__FILE__))}/../lib")
require 'tsm-accounting'

tsm = TSMAccounting::Database.new(File.new('data/TradeSkillMaster_Accounting.lua').read)
tsm.to_csv('/tmp/accounting.csv')
