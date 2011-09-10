lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)
require 'tsm-accounting.rb'

Gem::Specification.new do |s|
  s.name        = "tsm-accounting"
  s.version     = TSMAccounting::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["owlmanatt"]
  s.email       = ["owlmanatt@gmail.com"]
  s.homepage    = "https://github.com/OwlManAtt/TSM-Accounting"
  s.summary     = "Rubygem for accessing your TSM accounting savedvariable file."
  s.description = "It doesn't suck too badly maybe."
  s.required_rubygems_version = ">= 1.3.6"
  s.required_ruby_version = '>= 1.8.7'

  s.files        = Dir.glob("{lib}/**/*") + Dir.glob("{test/**/*}") + %w(AUTHORS HISTORY LICENSE README)
  s.require_path = 'lib'
end
