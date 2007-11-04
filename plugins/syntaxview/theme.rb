

module Redcar
  class Theme
    class << self
      attr_reader :themes
    end
    
    def self.load_themes
      # print "loading themes ["
      if File.exist?(SyntaxSourceView.cache_dir + "themes.dump")
        str = File.read(SyntaxSourceView.cache_dir + "themes.dump")
        @themes = Marshal.load(str)
        #puts " ... from cache]"
      else
        @themes = {}        
        Dir[SyntaxSourceView.themes_dir + "*"].each do |file|
          print "."
          xml = IO.readlines(file).join
          plist = Redcar::Plist.plist_from_xml(xml)
          @themes[plist[0]['name']] = Redcar::Theme.new(plist[0])
        end
        #puts "]"
        str = Marshal.dump(@themes)
        File.open(SyntaxSourceView.cache_dir + "themes.dump", "w") do |f|
          f.puts str
        end
      end
    end
    
#     def self.default_theme
#       @default_theme ||= theme(Theme.Preferences["Tab Theme"])
#     end
    
    def self.default_theme
      theme("Twilight")#Mac Classic")
    end
    
#     def self.set_theme(th)
#       th = theme(th)
#       @default_theme = th
#       Redcar["theme/default_theme"] = th.name
#       Redcar.current_window.all_tabs.each do |tab|
#         tab.set_theme(th)
#       end
#     end
    
    def self.theme(name)
      case name
      when String
        th = @themes[name]
        unless th
          puts "no such theme: #{name}\nthemes: #{@themes.keys.join(', ')}"
          th = @themes[@themes.keys.first]
        end
        th
      when Theme
        name
      end
    end
    
    def self.theme_names
      @themes.keys
    end
  end
end

module Redcar
  class Theme
#    include DebugPrinter
    attr_accessor :name, :uuid, :global_settings
  
    def initialize(hash)
      @name = hash['name']
      @uuid = hash['uuid']
      @global_settings = hash["settings"].find {|h| h.keys == ["settings"]}["settings"]
      @settings = hash["settings"].reject{|h| h.keys == ["settings"]}
    end
    
    # For a given scopename finds all the settings in the theme which apply to it.
    def settings_for_scope(scope, inner)
      scopes = scope.hierarchy_names(inner)
      scope_join = scopes.join(" ")
      #scope = scope.name
      @settings_for_scope ||= {}
      r = @settings_for_scope[scope_join]
      return r if r
      applicables = []
      @settings.each do |setting|
        if setting['scope']
          if rating = applicable?(setting['scope'], scopes)
            applicables << [rating, setting]
          end
        end
      end
      # need to rank them
      applicables = applicables.sort do |a, b|
        if a[0][0] > b[0][0]
          -1
        elsif a[0][0] < b[0][0]
          1
        elsif a[0][0] == b[0][0]
          k = nil
          n = [a[0][1].length, b[0][1].length].max
          0.upto(n-1) do |i|
            ae = a[0][1][i]
            be = b[0][1][i]
            if !k
              if ae and !be
                k = -1
              elsif be and !ae
                k = 1
              elsif ae > be
                k = -1
              elsif ae < be
                k = 1
              end
            end
          end
          k||0
        end
      end.map {|a| a[1]}
      @settings_for_scope[scope_join] = applicables
    end
    
    # Given a scope selector, returns its specificity. E.g keyword.if == 2 and string constant == 2
    def specificity(selector)
      selector.split(/\.|\s/).length
    end
    
    # Returns false if the selector is not applicable to the scope, and returns the specificity of the
    # selector if it is applicable.
    def applicable?(selector, scopes)
      # split by commas (which are ORs)
      selector.split(',').each do |subselector|
        subselector = subselector.strip
        
        positive_subselector, negative_subselector = 
          *subselector.split(" - ")
        positive_subselector_components = 
          positive_subselector.split(' ')
        if negative_subselector
          negative_subselector_components = 
            negative_subselector.split(' ')
        else
          negative_subselector_components = nil
        end
        
        #SyntaxLogger.debug { positive_subselector_components.inspect }
        #SyntaxLogger.debug { negative_subselector_components.inspect }
        
        # the bump along: (a la regular expressions)
        (scopes.length-1).downto(0) do |i|
          #SyntaxLogger.debug { "  checking at index: #{i}" }
          j = i
        #  last_matching_index = -1
          last_num_elements = Array.new(scopes.length, 0)
          pos_match = positive_subselector_components.all? do |comp|
            k = j-1
            match = scopes[j..-1].any? do |scope|
              k += 1
              scope.include? comp
            end
            #SyntaxLogger.debug { "      matched component #{comp.inspect} at #{k}" }
            if match
             # last_matching_index = j
              last_num_elements[k] = comp.split(".").length
            end
            j += 1
            match
          end
          if pos_match
            #SyntaxLogger.debug { "    pos_match" }
            if negative_subselector_components
              j -= 2
              neg_match = negative_subselector_components.all? do |comp|
                j += 1
                scopes[j..-1].any? do |scope|
                  scope.include? comp
                end
              end
            else
              neg_match = false
            end
          else
            #SyntaxLogger.debug { "    no pos_match" }
          end
          if pos_match and not neg_match
            #SyntaxLogger.debug { last_num_elements }
            spec = positive_subselector_components.
              inject(0) {|m, c| m += specificity(c) }
            last_matching_index = 0
            last_num_elements.each_with_index {|e, i| last_matching_index = i if e > 0}
            return [last_matching_index, last_num_elements.reverse]
          end
        end
        
#         # split on spaces (which are ANDs)
#         selector_components = subselector.split(' ')
#         prev_offset = -1
#         has_all = selector_components.inject(1) do |memo, comp|
#           if offset = scope.index(comp) and offset > prev_offset
        #             #SyntaxLogger.debug {"  has #{comp.inspect} at #{offset}"}
#             prev_offset = offset
#             memo
#           else
#             0
#           end
#         end
#         if has_all == 1
        #           #SyntaxLogger.debug { "has all required components" }
#           spec = selector_components.inject(0) {|m, c| m += specificity(c) }
#           return spec 
#         end
       end
      false
    end
    
    def self.parse_colour(str_colour)
      Gdk::Color.parse(clean_colour(str_colour))
    end
    
    def self.clean_colour(str_colour)
      return nil unless str_colour
      if str_colour.length == 7
        str_colour
      elsif str_colour.length == 9
        # FIXME: what are the extra two hex values for? 
        # (possibly they are an opacity)
        # #12345678
        #'#'+str_colour[3..-1]
        r = str_colour[1..2].hex
        g = str_colour[3..4].hex
        b = str_colour[5..6].hex
        t = str_colour[7..8].hex
        r = (r*t)/255
        g = (g*t)/255
        b = (b*t)/255
        '#'+("%02x"%r)+("%02x"%g)+("%02x"%b)
#        str_colour[0..6]
      end
    end
    
    def self.textmate_settings_to_pango_options(settings)
      v = settings["pango"]
      return v if v
      options = { :foreground => self.clean_colour(settings["foreground"]),
                  :background => self.clean_colour(settings["background"]) }
      options = options.delete_if{|k, v| !v}
      settings["fontStyle"] ||= ""
      if settings["fontStyle"].include? "italic"
        options[:style] = Pango::STYLE_ITALIC
      end
      if settings["fontStyle"].include? "underline"
        options[:underline] = Pango::UNDERLINE_LOW
      end
      if settings["fontStyle"].include? "bold"
        options[:weight] = Pango::WEIGHT_BOLD
      end
      settings["pango"] = options
    end
  end
end