module Crysterm
  class Widget < ::Crysterm::Object
    # module Content
    include Helpers

    # Can element's content be word-wrapped?
    property? wrap_content = true

    # Is element's content to be parsed for tags?
    property? parse_tags = true

    getter! tabc : String

    # Alignment of contained text
    property align : Tput::AlignFlag = Tput::AlignFlag::Top | Tput::AlignFlag::Left

    # Widget's user-set content in original form. Includes any attributes and tags.
    getter content : String = ""

    # Printable, word-wrapped content, ready for rendering into the element.
    property _pcontent : String?

    property _clines = CLines.new

    # Processes and sets widget content. Does not allow extra options re.
    # how content is to be processed; use `#set_content` if you need to provide
    # extra options.
    def content=(content)
      set_content content
    end

    def set_content(content = "", no_clear = false, no_tags = false)
      clear_last_rendered_position unless no_clear

      # XXX make it possible to have `update_context`, which only updates
      # internal structures, not @content (for rendering purposes, where
      # original content should not be modified).
      @content = content

      process_content(no_tags)
      emit(Crysterm::Event::SetContent)
    end

    def get_content
      return "" if @_clines.empty?
      @_clines.fake.join "\n"
    end

    def set_text(content = "", no_clear = false)
      content = content.gsub SGR_REGEX, ""
      set_content content, no_clear, true
    end

    def get_text
      get_content.gsub SGR_REGEX, ""
    end

    class CLines < Array(String)
      property string = ""
      property max_width = 0
      property width = 0

      property content : String = ""

      property real = [] of String

      property fake = [] of String

      property ftor = [] of Array(Int32)
      property rtof = [] of Int32
      property ci = [] of Int32

      property attr : Array(Int32)? = [] of Int32

      property ci = [] of Int32
    end

    def process_content(no_tags = false)
      return false unless @screen # XXX why?

      Log.trace { "Parsing widget content: #{@content.inspect}" }

      colwidth = awidth - iwidth
      if (@_clines.nil? || @_clines.empty? || @_clines.width != colwidth || @_clines.content != @content)
        content =
          @content.gsub(/[\x00-\x08\x0b-\x0c\x0e-\x1a\x1c-\x1f\x7f]/, "")
            .gsub(/\e(?!\[[\d;]*m)/, "") # SGR
            .gsub(/\r\n|\r/, "\n")
            .gsub(/\t/, @tabc)

        Log.trace { "Internal content is #{content.inspect}" }

        if true # (screen.full_unicode)
          # double-width chars will eat the next char after render. create a
          # blank character after it so it doesn't eat the real next char.
          # TODO
          # content = content.replace(unicode.chars.all, '$1\x03')

          # iTerm2 cannot render combining characters properly.
          if screen.display.tput.emulator.iterm2?
            # TODO
            # content = content.replace(unicode.chars.combining, "")
          end
        else
          # no double-width: replace them with question-marks.
          # TODO
          # content = content.gsub unicode.chars.all, "??"
          # delete combining characters since they're 0-width anyway.
          # Note: We could drop this, the non-surrogates would get changed to ? by
          # the unicode filter, and surrogates changed to ? by the surrogate
          # regex. however, the user might expect them to be 0-width.
          # Note: Might be better for performance to drop it!
          # TODO
          # content = content.replace(unicode.chars.combining, '')
          # no surrogate pairs: replace them with question-marks.
          # TODO
          # content = content.replace(unicode.chars.surrogate, '?')
          # XXX Deduplicate code here:
          # content = helpers.dropUnicode(content)
        end

        if !no_tags
          content = _parse_tags content
        end
        Log.trace { "After _parse_tags: #{content.inspect}" }

        @_clines = _wrap_content(content, colwidth)
        @_clines.width = colwidth
        @_clines.content = @content
        @_clines.attr = _parse_attr @_clines
        @_clines.ci = [] of Int32
        @_clines.reduce(0) do |total, line|
          @_clines.ci.push(total)
          total + line.size + 1
        end

        @_pcontent = @_clines.join "\n"
        emit Crysterm::Event::ParsedContent

        return true
      end

      # Need to calculate this every time because the default fg/bg may change.
      @_clines.attr = _parse_attr(@_clines) || @_clines.attr

      false
    end

    # Convert `{red-fg}foo{/red-fg}` to `\e[31mfoo\e[39m`.
    def _parse_tags(text)
      if (!@parse_tags)
        return text
      end
      unless (text =~ /{\/?[\w\-,;!#]*}/)
        return text
      end

      outbuf = ""
      # state

      bg = [] of String
      fg = [] of String
      flag = [] of String

      cap = nil
      # slash
      # param
      # attr
      esc = nil

      loop do
        if (!esc && (cap = text.match /^{escape}/))
          text = text[cap[0].size..]
          esc = true
          next
        end

        if (esc && (cap = text.match /^([\s\S]+?){\/escape}/))
          text = text[cap[0].size..]
          outbuf += cap[1]
          esc = false
          next
        end

        if (esc)
          # raise "Unterminated escape tag."
          outbuf += text
          break
        end

        # Matches {normal}{/normal} and all other tags
        if (cap = text.match /^{(\/?)([\w\-,;!#]*)}/)
          text = text[cap[0].size..]
          slash = (cap[1] == "/")
          # XXX Tags must be specified such as {light-blue-fg}, but are then
          # parsed here with - being ' '. See why? Can we work with - and skip
          # this replacement part?
          param = (cap[2].gsub(/-/, ' '))

          if (param == "open")
            outbuf += '{'
            next
          elsif (param == "close")
            outbuf += '}'
            next
          end

          if (param[-3..]? == " bg")
            state = bg
          elsif (param[-3..]? == " fg")
            state = fg
          else
            state = flag
          end

          if (slash)
            if (!param || param.blank?)
              outbuf += screen.display.tput._attr("normal") || ""
              bg.clear
              fg.clear
              flag.clear
            else
              attr = screen.display.tput._attr(param, false)
              if (attr.nil?)
                outbuf += cap[0]
              else
                # D O:
                # if (param !== state[state.size - 1])
                #   throw new Error('Misnested tags.')
                # }
                state.pop
                if (state.size > 0)
                  outbuf += screen.display.tput._attr(state[-1]) || ""
                else
                  outbuf += attr
                end
              end
            end
          else
            if (!param)
              outbuf += cap[0]
            else
              attr = screen.display.tput._attr(param)
              if (attr.nil?)
                outbuf += cap[0]
              else
                state.push(param)
                outbuf += attr
              end
            end
          end

          next
        end

        if (cap = text.match /^[\s\S]+?(?={\/?[\w\-,;!#]*})/)
          text = text[cap[0].size..]
          outbuf += cap[0]
          next
        end

        outbuf += text
        break
      end

      outbuf
    end

    def _parse_attr(lines : CLines)
      dattr = sattr(style)
      attr = dattr
      attrs = [] of Int32
      # line
      # i
      # j
      # c

      if (lines[0].attr == attr)
        return
      end

      (0...lines.size).each do |j|
        line = lines[j]
        attrs.push attr
        unless attrs.size == j + 1
          raise "indexing error"
        end
        (0...line.size).each do |i|
          if (line[i] == '\e')
            if (c = line[1..].match SGR_REGEX)
              attr = screen.attr2code(c[0], attr, dattr)
              # i += c[0].size - 1 # Unused
            end
          end
        end
        # j += 1 # Unused
      end

      attrs
    end

    # Wraps content based on available widget width
    def _wrap_content(content, colwidth)
      default_state = @align
      wrap = @wrap_content
      margin = 0
      rtof = [] of Int32
      ftor = [] of Array(Int32)
      # outbuf = [] of String
      outbuf = CLines.new
      # line
      # align
      # cap
      # total
      # i
      # part
      # j
      # lines
      # rest

      if !content || content.empty?
        outbuf.push(content)
        outbuf.rtof = [0]
        outbuf.ftor = [[0]]
        outbuf.fake = [] of String
        outbuf.real = outbuf
        outbuf.max_width = 0
        return outbuf
      end

      lines = content.split "\n"

      if @scrollbar
        margin += 1
      end
      if is_a? Widget::TextArea
        margin += 1
      end
      if (colwidth > margin)
        colwidth -= margin
      end

      # What follows is a relatively large loop with subloops, all implemented with 'loop do'.
      # This is to simultaneously work around 2 issues in Crystal -- (1) not having loop labels,
      # and (2) while loop mistakenly not returning break's return value. Elegance is impacted.

      #      main:
      no = 0
      # NOTE Done with loop+break due to https://github.com/crystal-lang/crystal/issues/1277
      loop do
        break unless no < lines.size

        line = lines[no]
        align = default_state
        align_left_too = false

        ftor.push [] of Int32

        # Handle alignment tags.
        if @parse_tags
          if (cap = line.match /^{(left|center|right)}/)
            align_left_too = true
            line = line[cap[0].size..]
            align = default_state = case cap[1]
                                    when "center"
                                      Tput::AlignFlag::Center
                                    when "left"
                                      Tput::AlignFlag::Left
                                    else
                                      Tput::AlignFlag::Right
                                    end
          end
          if (cap = line.match /{\/(left|center|right)}$/)
            line = line[0...(line.size - cap[0].size)]
            # Reset default_state to whatever alignment the widget has by default.
            default_state = @align
          end
        end

        # If the string could be too long, check it in more detail and wrap it if needed.
        # NOTE Done with loop+break due to https://github.com/crystal-lang/crystal/issues/1277
        loop_ret = loop do
          break unless line.size > colwidth

          # Measure the real width of the string.
          total = 0
          i = 0
          # NOTE Done with loop+break due to https://github.com/crystal-lang/crystal/issues/1277
          loop do
            break unless i < line.size
            while (line[i] == '\e')
              while (line[i] && line[i] != 'm')
                i += 1
              end
            end
            if (line[i]?.nil?)
              break
            end
            total += 1
            if total == colwidth # If we've reached the end of available width of bounding box
              i += 1
              # If we're not wrapping the text, we have to finish up the rest of
              # the control sequences before cutting off the line.
              unless @wrap_content
                rest = line[i..].scan(/\e\[[^m]*m/) # SGR
                rest = rest.any? ? rest.join : ""
                outbuf.push _align(line[0...i] + rest, colwidth, align, align_left_too)
                ftor[no].push(outbuf.size - 1)
                rtof.push(no)
                break :main
              end
              # XXX TODO
              # if (!screen.fullUnicode)
              # Try to find a char to break on.
              if (i != line.size)
                j = i
                # TODO how can the condition and subsequent IF ever match
                # with the line[j] thing?
                while ((j > i - 10) && (j > 0) && (j -= 1) && (line[j] != ' '))
                  if (line[j] == ' ')
                    i = j + 1
                  end
                end
              end
              # end
              break
            end
            i += 1
          end

          part = line[0...i]
          line = line[i..]

          outbuf.push _align(part, colwidth, align, align_left_too)
          ftor[no].push(outbuf.size - 1)
          rtof.push(no)

          # Make sure we didn't wrap the line at the very end, otherwise
          # we'd get an extra empty line after a newline.
          if line == ""
            break :main
          end

          # If only an escape code got cut off, add it to `part`.
          if (line.matches? /^(?:\e[\[\d;]*m)+$/) # SGR
            outbuf[outbuf.size - 1] += line
            break :main
          end
        end

        if loop_ret == :main
          no += 1
          next
        end

        outbuf.push(_align(line, colwidth, align, align_left_too))
        ftor[no].push(outbuf.size - 1)
        rtof.push(no)

        no += 1
      end

      outbuf.rtof = rtof
      outbuf.ftor = ftor
      outbuf.fake = lines
      outbuf.real = outbuf

      # Note that this is intended to save the length of the longest line to
      # outbuf.max_width. In the case that the text was aligned, the alignment
      # has padded it with spaces, effectively lengthening it. So, in that case
      # the max_width value won't be actual max. length of longest line, but it
      # will be the full width of the surrounding box, to which it was aligned.
      outbuf.max_width = outbuf.reduce(0) do |current, line|
        line = line.gsub(SGR_REGEX, "")
        line.size > current ? line.size : current
      end

      outbuf
    end

    # Aligns content
    def _align(line, width, align = Tput::AlignFlag::None, align_left_too = false)
      return line if align.none?

      cline = line.gsub SGR_REGEX, ""
      len = cline.size

      # XXX In blessed's code (and here) it was done only with this commented
      # line below. But after/around the May 28 2021 changes, this stopped
      # centering texts. Upon investigation, it was found this is because a
      # Layout sets all its children to #resizable=true (shrink=true in blessed),
      # so the free width (s) results being 0 here. But why this code worked
      # up to May is unexplained, since no obvious changes were done in this
      # code. Or, cn this be a bug we unintentionally fixed?
      # s = @resizable ? 0 : width - len
      s = (@resizable && !width) ? 0 : width - len

      return line if len == 0
      return line if s < 0

      if (align & Tput::AlignFlag::HCenter) != Tput::AlignFlag::None
        s = " " * (s//2)
        return s + line + s
      elsif align.right?
        s = " " * s
        return s + line
      elsif align_left_too && align.left?
        # Technically, left align is visually the same as no align at all.
        # But when text is aligned to center or right, all the available empty space is padded
        # with spaces (around the text in center align, and in front of text in right align).
        # So, because of this padding with spaces, which affects the size of the widget, we
        # want to pad {left} align for uniformity as well.
        #
        # But, because aligning left affects almost everything in undesired ways (a lot
        # more chars are present, and cursor in text widgets is wrong), we do not want to do
        # this when Widget's `align = AlignFlag::Left`. We only want to do it when there is
        # "{left}" in content, and parse_tags is true.
        #
        # This should ensure that {left|center|right} behave 100% identical re. the effect
        # it has on row width. To see the old behavior without this, comment this elseif,
        # run test/widget-list.cr, and observe the look of the first element in the list
        # vs. the other elements when they are selected.
        s = " " * s
        return line + s
      elsif @parse_tags && line.index /\{|\}/
        # XXX This is basically Tput::AlignFlag::Spread, but not sure
        # how to put that as a flag yet. Maybe this (or another)
        # widget flag could mean to spread words to fill up the whole
        # line, increasing spaces between them?
        parts = line.split /\{|\}/

        cparts = cline.split /\{|\}/
        if cparts[0]? && cparts[2]? # Don't trip on just single { or }
          s = Math.max(width - cparts[0].size - cparts[2].size, 0)
          s = " " * s
          return "#{parts[0]}#{s}#{parts[2]}"
        else
          # Nothing; will default to returning `line` below.
        end
      end

      line
    end

    def insert_line(i = nil, line = "")
      if (line.is_a? String)
        line = line.split("\n")
      end

      if (i.nil?)
        i = @_clines.ftor.size
      end

      i = Math.max(i, 0)

      while (@_clines.fake.size < i)
        @_clines.fake.push("")
        @_clines.ftor.push([@_clines.push("").size - 1])
        @_clines.rtof[@_clines.fake.size - 1]
      end

      # NOTE: Could possibly compare the first and last ftor line numbers to see
      # if they're the same, or if they fit in the visible region entirely.
      start = @_clines.size
      # diff
      # real

      if (i >= @_clines.ftor.size)
        real = @_clines.ftor[@_clines.ftor.size - 1]
        real = real[-1] + 1
      else
        real = @_clines.ftor[i][0]
      end

      line.size.times do |j|
        @_clines.fake.insert(i + j, line[j])
      end

      set_content(@_clines.fake.join("\n"), true)

      diff = @_clines.size - start

      if (diff > 0)
        pos = _get_coords
        if (!pos || pos == 0)
          return
        end

        height = pos.yl - pos.yi - iheight
        base = @child_base
        visible = real >= base && real - base < height

        if (pos && visible && screen.clean_sides(self))
          screen.insert_line(diff,
            pos.yi + itop + real - base,
            pos.yi,
            pos.yl - ibottom - 1)
        end
      end
    end

    def delete_line(i = nil, n = 1)
      if (i.nil?)
        i = @_clines.ftor.size - 1
      end

      i = Math.max(i, 0)
      i = Math.min(i, @_clines.ftor.size - 1)

      # NOTE: Could possibly compare the first and last ftor line numbers to see
      # if they're the same, or if they fit in the visible region entirely.
      start = @_clines.size
      # diff
      real = @_clines.ftor[i][0]

      while (n > 0)
        n -= 1
        @_clines.fake.delete_at i
      end

      set_content(@_clines.fake.join("\n"), true)

      diff = start - @_clines.size

      # XXX clear_last_rendered_position() without diff statement?
      height = 0

      if (diff > 0)
        pos = _get_coords
        if (!pos || pos == 0)
          return
        end

        height = pos.yl - pos.yi - iheight

        base = @child_base
        visible = real >= base && real - base < height

        if (pos && visible && screen.clean_sides(self))
          screen.delete_line(diff,
            pos.yi + itop + real - base,
            pos.yi,
            pos.yl - ibottom - 1)
        end
      end

      if (@_clines.size < height)
        clear_last_rendered_position
      end
    end

    def insert_top(line)
      fake = @_clines.rtof[@child_base]
      insert_line(fake, line)
    end

    def insert_bottom(line)
      h = (@child_base) + aheight - iheight
      i = Math.min(h, @_clines.size)
      fake = @_clines.rtof[i - 1] + 1

      insert_line(fake, line)
    end

    def delete_top(n = 1)
      fake = @_clines.rtof[@child_base]
      delete_line(fake, n)
    end

    def delete_bottom(n)
      h = (@child_base) + aheight - 1 - iheight
      i = Math.min(h, @_clines.size - 1)
      fake = @_clines.rtof[i]

      n = 1 if !n || n == 0

      delete_line(fake - (n - 1), n)
    end

    def set_line(i, line)
      i = Math.max(i, 0)
      while (@_clines.fake.size < i)
        @_clines.fake.push("")
      end
      @_clines.fake[i] = line
      set_content(@_clines.fake.join("\n"), true)
    end

    def set_baseline(i, line)
      fake = @_clines.rtof[@child_base]
      set_line(fake + i, line)
    end

    def get_line(i)
      i = Math.max(i, 0)
      i = Math.min(i, @_clines.fake.size - 1)
      @_clines.fake[i]
    end

    def get_baseline(i)
      fake = @_clines.rtof[@child_base]
      get_line(fake + i)
    end

    def clear_line(i)
      i = Math.min(i, @_clines.fake.size - 1)
      set_line(i, "")
    end

    def clear_base_line(i)
      fake = @_clines.rtof[@child_base]
      clear_line(fake + i)
    end

    def unshift_line(line)
      insert_line(0, line)
    end

    def shift_line(n)
      delete_line(0, n)
    end

    def push_line(line)
      if (!@content)
        return set_line(0, line)
      end
      insert_line(@_clines.fake.size, line)
    end

    def pop_line(n)
      delete_line(@_clines.fake.size - 1, n)
    end

    def get_lines
      @_clines.fake.dup
    end

    def get_screen_lines
      @_clines.dup
    end

    def str_width(text)
      text = @parse_tags ? strip_tags(text) : text
      # return screen.full_unicode ? unicode.str_width(text) : helpers.drop_unicode(text).size
      # text = text
      text.size # or bytesize?
    end
  end

  class StringIndex
    def initialize(@object : String) : String?
    end

    def [](i : Int)
      i < 0 ? nil : @object[i]
    end

    def []?(i : Int)
      i < 0 ? nil : @object[i]?
    end

    def [](range : Range)
      @object[range]
    end

    # def []?(range : Range)
    # @object[range]
    # end

    def size
      @object.size
    end
    # end
  end
end
