require 'csv'

module TSMAccounting
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
          @data[realm_name][faction_name]['sale'] = parse_rope(faction_data['sell'])
          @data[realm_name][faction_name]['purchase'] = parse_rope(faction_data['buy'])
        end # faction
      end # realms
    end # initialize

    def to_csv(output_file)
      CSV.open(output_file, 'w') do |f|
        f << ['Realm','Faction','Transaction Type','Time','Item','Quantity','Stack Size','Price (c)','Buyer','Seller']

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

    def parse_rope(rope)
      list = {}
      rope.split('?').each do |row|
        item = Item.new(row)

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

    def initialize(item)
      encoded_item, encoded_records = item.split '!'
     
      if encoded_item[0,1] == 'x'
        @name = decode_code(encoded_item)
      else
        @name = decode_link(encoded_item)
      end    
      @transactions = encoded_records.split('@').map {|record| Transaction.new(record) }
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

    def initialize(encoded_string)
      d = encoded_string.split('#')

      @stack_size = decode(d[0])
      @quantity = decode(d[1])
      @datetime = Time.at(decode(d[2]))
      @price = decode(d[3])
      @buyer = d[4] 
      @seller = d[5] 
    end # initialize

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
