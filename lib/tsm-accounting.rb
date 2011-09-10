# Copyright (c) 2011, Nicholas 'OwlManAtt' Evans <owlmanatt@gmail.com>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
# 
#   * Redistributions of source code must retain the above copyright notice, this
#     list of conditions and the following disclaimer.
# 
#   * Redistributions in binary form must reproduce the above copyright notice, 
#     this list of conditions and the following disclaimer in the documentation 
#     and/or other materials provided with the distribution.
# 
#   * Neither the name of the Yasashii Syndicate nor the names of its contributors 
#     may be used to endorse or promote products derived from this software 
#     without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE 
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE 
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL 
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR 
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER 
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
# TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF 
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
require 'csv'

module TSMAccounting
  VERSION = '0.9.0'

  class Database
    attr_reader :data
    # Expects the whole TradeSkillMaster_Accounting.lua file
    # as a string.
    def initialize(db_string)
      database = extract_data(db_string)
      
      @data = {}
      database.each do |realm_name,realm_data|
        @data[realm_name] = {} unless @data.has_key? realm_name
        realm_data.each do |faction_name,faction_data|
          @data[realm_name][faction_name] = {} unless @data[realm_name].has_key? faction_name
          @data[realm_name][faction_name]['sale'] = parse_rope(faction_data['sell'],'sale')
          @data[realm_name][faction_name]['purchase'] = parse_rope(faction_data['buy'],'purchase')
        end # faction
      end # realms
    end # initialize

    def to_csv(output_file)
      CSV.open(output_file, 'w') do |f|
        f << ['Realm','Faction','Transaction Type','Time','Item','Quantity','Stack Size','Price (g)','Price (c)','Buyer','Seller']

        @data.each do |realm,factions|
          factions.each do |faction,ropes|
            ropes.each do |type,items|
              items.each do |name,item|
                item.transactions.each do |tx|
                  row = [realm,faction,type] 
                  row << tx.datetime.strftime('%Y-%m-%d %k:%M:%S')
                  row << item.name
                  row << tx.quantity
                  row << tx.stack_size
                  row << tx.usable_price
                  row << tx.price
                  row << tx.buyer
                  row << tx.seller

                  f << row
                end
              end
            end
          end
        end
      end # close CSV
    end # to_csv

    protected 
    def extract_data(db)
      # OK, we have a big pile of lua shit. It's structured like so:
      #
      # TradeSkillMaster_AccountingDB = {
      #   ["useless shit"] = {
      #     ["more keys"] = { . . . }
      #   }
      #   ["factionrealm"] = {
      #     ["Alliance - Trollbane"] = {
      #       ["sellDataRope"] = "data"
      #       ["tooltip"] = {
      #         ["sale"] = true,
      #       },
      #       ["buyDataRope"] = "data"
      #     }
      #   }
      # }
      #
      # @TODO Some memory usage can be saved by taking a file handler
      #       and doing #each_line instead of having the whole file read in
      #       and broken in to an array at once. This isn't a big deal for
      #       my file since the only two lines of consequence are the ones I'm
      #       going to be saving anyway but it may be a good idea if there's a
      #       goblin operating on both factions for six realms...
      
      depth = 0
      realm, faction = nil
      data = {}
      db.split("\n").each do |line|
        if line =~ /^\s*\["factionrealm"\]/
          depth = 1
          next
        end
        
        if depth == 1
          match = line.match(/^\s*\["(.*)"\]\s*=\s*\{/)
          if match
            depth = 2
            faction, realm = match[1].split ' - ' 
            
            data[realm] = {} unless data.has_key? realm
            data[realm][faction] = {} unless data[realm].has_key? faction

            next
          end

          if line.match(/\s*\}/)
            depth = 1
            next
          end
        end # depth1

        if depth == 2
          match = line.match(/^\s*\["(buy|sell)DataRope"\]/)
          if match
            line.gsub!(/",\s*$/,'').gsub!(/^\s*\["(buy|sell)DataRope"\]\s*=\s*"/,'')
            data[realm][faction][match[1]] = line
            next
          elsif line =~ /^\s*\["/
            depth = 3
            next
          end

          if line.match(/\s*\}/)
            depth = 1
            next
          end
        end # depth2

        # tooltip shit, fuck off and die.
        if depth == 3
          if line.match(/\s*\}/)
            depth = 2
            next
          end
        end # depth3

        if line.match(/\s*\}/)
          depth = 0
          next
        end
      end # line depth0

      return data
    end # extract_data

    def parse_rope(rope,type)
      list = {}
      rope.split('?').each do |row|
        item = Item.new(row,type)

        if list.has_key? item.name
          # merge
        else
          list[item.name] = item
        end
      end
      
     return list 
    end # parse_rope
  end # Database

  class Item
    attr_reader :name, :transactions

    def initialize(item,type)
      encoded_item, encoded_records = item.split '!'
     
      if encoded_item[0,1] == 'x'
        @name = decode_code(encoded_item)
      else
        @name = decode_link(encoded_item)
      end    
      @transactions = encoded_records.split('@').map {|record| Transaction.new(record,type) }
      @transactions ||= []
    end # initialize

    protected 
    def decode_link(text)
      colour, code, name = text.split '|'

      return name 
    end # decode_link

    # I _think_ this will only get called if the item link cannot
    # be resolved by TSM for some reason. I am guessing it will
    # store the raw item code (as opposed to, you know, nothing).
    #
    # In theory, this shouldn't get called...
    def decode_code(text)
      return text 
    end # decode_string
  end # item

  class Transaction
    attr_reader :stack_size, :quantity, :datetime, :price, :buyer, :seller

    def initialize(encoded_string,type)
      d = encoded_string.split('#')

      @stack_size = decode(d[0])
      @quantity = decode(d[1])
      @datetime = Time.at(decode(d[2]))
      @price = decode(d[3])

      if type == 'purchase'
        @buyer = d[5]
        @seller = d[4]
      else
        @buyer = d[4] 
        @seller = d[5] 
      end
    end # initialize

    def usable_price
      price = @price.to_s.rjust(5,'0')
      parts = {
        'gold' => price[0..-5].to_i,
        'silver' => price[-4..2].to_i,
        'copper' => price[-2..2].to_i
      }

      # Round up the copper.
      parts['silver'] += 1 if parts['copper'] > 50

      # If this was a <50c transaction, set silver to 1 so
      # it doesn't confuse people.
      if parts['gold'] == 0 and parts['silver'] == 0 and parts['copper'] < 50
        parts['silver'] = 1
      end
      
      return "#{parts['gold']}.#{parts['silver']}".to_f
    end

    protected
    def decode(value)
      alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_="
      base = alpha.length

      i = value.length - 1
      result = 0
      value.each_char do |w|
        if w.match(/([A-Za-z0-9_=])/)
          result += (alpha.index(w)) * (base**i)
          i -= 1
        end
      end

      return result
    end # decode
    end # Transaction
end # TSMAccounting
