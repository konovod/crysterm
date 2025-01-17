module Crysterm
  class Widget < ::Crysterm::Object
    # module Rendering
    include Crystallabs::Helpers::Alias_Methods

    property items = [] of Widget::Box

    # What action to take when widget rendering would overflow parent's rectangle?
    property overflow = Overflow::Ignore

    # Here be dragons

    # Renders all child elements into the output buffer.
    def _render(with_children = true)
      emit Crysterm::Event::PreRender

      # XXX TODO Is this a hack in Crysterm? It allows elements within lists to be styled as appropriate.
      style = self.style
      parent.try do |parent2|
        if parent2._is_list && parent2.is_a? Widget::List
          if parent2.items[parent2.selected]? == self
            style = parent2.style.selected
          else
            style = parent2.style.item
          end
        end
      end

      process_content

      coords = _get_coords(true)
      unless coords
        @lpos = nil
        return
      end

      if (coords.xl - coords.xi <= 0)
        coords.xl = Math.max(coords.xl, coords.xi)
        return
      end

      if (coords.yl - coords.yi <= 0)
        coords.yl = Math.max(coords.yl, coords.yi)
        return
      end

      lines = screen.lines
      xi = coords.xi
      xl = coords.xl
      yi = coords.yi
      yl = coords.yl
      # x
      # y
      # cell
      # attr
      # ch
      # Log.trace { lines.inspect }
      content = StringIndex.new @_pcontent || ""
      ci = @_clines.ci[coords.base]? || 0 # XXX Is it ok that array lookup can be nil? and defaulting to 0?
      # battr
      # dattr
      # c
      # visible
      # i
      bch = style.char

      # D O:
      # Clip content if it's off the edge of the screen
      # if (xi + ileft < 0 || yi + itop < 0)
      #   clines = @_clines.slice()
      #   if (xi + ileft < 0)
      #     for (i = 0; i < clines.size; i++)
      #       t = 0
      #       csi = ''
      #       csis = ''
      #       for (j = 0; j < clines[i].size; j++)
      #         while (clines[i][j] == '\e')
      #           csi = '\e'
      #           while (clines[i][j++] != 'm') csi += clines[i][j]
      #           csis += csi
      #         end
      #         if (++t == -(xi + ileft) + 1) break
      #       end
      #       clines[i] = csis + clines[i].substring(j)
      #     end
      #   end
      #   if (yi + itop < 0)
      #     clines = clines.slice(-(yi + itop))
      #   end
      #   content = clines.join('\n')
      # end

      if (coords.base >= @_clines.ci.size)
        # Can be @_pcontent, but this is the same here, plus not_nil!
        ci = content.size
      end

      @lpos = coords

      @border.try do |border|
        if border.type.line?
          screen._border_stops[coords.yi] = true
          screen._border_stops[coords.yl - 1] = true
          # D O:
          # if (!screen._border_stops[coords.yi])
          #   screen._border_stops[coords.yi] = { xi: coords.xi, xl: coords.xl }
          # else
          #   if (screen._border_stops[coords.yi].xi > coords.xi)
          #     screen._border_stops[coords.yi].xi = coords.xi
          #   end
          #   if (screen._border_stops[coords.yi].xl < coords.xl)
          #     screen._border_stops[coords.yi].xl = coords.xl
          #   end
          # end
          # screen._border_stops[coords.yl - 1] = screen._border_stops[coords.yi]
        end
      end

      dattr = sattr style
      attr = dattr

      # If we're in a scrollable text box, check to
      # see which attributes this line starts with.
      if (ci > 0)
        attr = @_clines.attr.try(&.[Math.min(coords.base, @_clines.size - 1)]?) || 0
      end

      if @border
        xi += 1
        xl -= 1
        yi += 1
        yl -= 1
      end

      # If we have padding/valign, that means the
      # content-drawing loop will skip a few cells/lines.
      # To deal with this, we can just fill the whole thing
      # ahead of time. This could be optimized.
      if (@padding.any? || (!@align.top?))
        if transparency = style.transparency
          (Math.max(yi, 0)...yl).each do |y|
            if !lines[y]?
              break
            end
            (Math.max(xi, 0)...xl).each do |x|
              if !lines[y][x]?
                break
              end
              lines[y][x].attr = Colors.blend(attr, lines[y][x].attr, alpha: transparency)
              # D O:
              # lines[y][x].char = bch
              lines[y].dirty = true
            end
          end
        else
          screen.fill_region(dattr, bch, xi, xl, yi, yl)
        end
      end

      if @padding.any?
        xi += @padding.left
        xl -= @padding.right
        yi += @padding.top
        yl -= @padding.bottom
      end

      # Determine where to place the text if it's vertically aligned.
      if @align.v_center? || @align.bottom?
        visible = yl - yi
        if (@_clines.size < visible)
          if @align.v_center?
            visible = visible // 2
            visible -= @_clines.size // 2
          elsif @align.bottom?
            visible -= @_clines.size
          end
          ci -= visible * (xl - xi)
        end
      end

      # Draw the content and background.
      # yi.step to: yl-1 do |y|
      (yi...yl).each do |y|
        if (!lines[y]?)
          if (y >= screen.aheight || yl < ibottom)
            break
          else
            next
          end
        end
        # TODO - make cell exist only if there's something to be drawn there?
        x = xi - 1
        while x < xl - 1
          x += 1
          cell = lines[y][x]?
          unless cell
            if x >= screen.awidth || xl < iright
              break
            else
              next
            end
          end

          ch = content[ci]? || bch
          # Log.trace { ci }
          ci += 1

          # D O:
          # if (!content[ci] && !coords._content_end)
          #   coords._content_end = { x: x - xi, y: y - yi }
          # end

          # Handle escape codes.
          while (ch == '\e')
            cnt = content[(ci - 1)..]
            if c = cnt.match SGR_REGEX_AT_BEGINNING
              ci += c[0].size - 1
              attr = screen.attr2code(c[0], attr, dattr)
              # Ignore foreground changes for selected items.
              parent.try do |parent2|
                if parent2._is_list && parent2.interactive? && parent2.is_a?(Widget::List) && parent2.items[parent2.selected] == self # XXX && parent2.invert_selected
                  attr = (attr & ~(0x1ff << 9)) | (dattr & (0x1ff << 9))
                end
              end
              ch = content[ci]? || bch
              ci += 1
            else
              break
            end
          end

          # Handle newlines.
          if (ch == '\t')
            ch = bch
          end
          if (ch == '\n')
            # If we're on the first cell and we find a newline and the last cell
            # of the last line was not a newline, let's just treat this like the
            # newline was already "counted".
            if ((x == xi) && (y != yi) && (content[ci - 2]? != '\n'))
              x -= 1
              next
            end
            # We could use fill_region here, name the
            # outer loop, and continue to it instead.
            ch = bch
            while (x < xl)
              cell = lines[y][x]?
              if (!cell)
                break
              end
              if transparency = style.transparency
                lines[y][x].attr = Colors.blend(attr, lines[y][x].attr, alpha: transparency)
                if content[ci - 1]?
                  lines[y][x].char = ch
                end
                lines[y].dirty = true
              else
                if cell != {attr, ch}
                  lines[y][x].attr = attr
                  lines[y][x].char = ch
                  lines[y].dirty = true
                end
              end
              x += 1
            end

            # It was a newline; we've filled the row to the end, we
            # can move to the next row.
            next
          end

          # TODO
          # if (screen.full_unicode && content[ci - 1])
          if (content.try &.[ci - 1]?)
            # point = content.codepoint_at(ci - 1) # Unused
            # TODO
            # # Handle combining chars:
            # # Make sure they get in the same cell and are counted as 0.
            # if (unicode.combining[point])
            #  if (point > 0x00ffff)
            #    ch = content[ci - 1] + content[ci]
            #    ci++
            #  end
            #  if (x - 1 >= xi)
            #    lines[y][x - 1][1] += ch
            #  elsif (y - 1 >= yi)
            #    lines[y - 1][xl - 1][1] += ch
            #  end
            #  x-=1
            #  next
            # end
            # Handle surrogate pairs:
            # Make sure we put surrogate pair chars in one cell.
            # if (point > 0x00ffff)
            #  ch = content[ci - 1] + content[ci]
            #  ci++
            # end
          end

          unless style.fill?
            next
          end

          if transparency = style.transparency
            lines[y][x].attr = Colors.blend(attr, lines[y][x].attr, alpha: transparency)
            if content[ci - 1]?
              lines[y][x].char = ch
            end
            lines[y].dirty = true
          else
            if cell != {attr, ch}
              lines[y][x].attr = attr
              lines[y][x].char = ch
              lines[y].dirty = true
            end
          end
        end
      end

      # Draw the scrollbar.
      # Could possibly draw this after all child elements.
      if coords.no_top? || coords.no_bottom?
        i = -Int32::MAX
      end
      @scrollbar.try do # |scrollbar|
      # D O:
      # i = @get_scroll_height()
        i = Math.max @_clines.size, _scroll_bottom

        if ((yl - yi) < i)
          x = xl - 1
          if style.scrollbar.ignore_border? && @border
            x += 1
          end
          if @always_scroll
            y = @child_base / (i - (yl - yi))
          else
            y = (@child_base + @child_offset) / (i - 1)
          end
          y = yi + ((yl - yi) * y).to_i
          if (y >= yl)
            y = yl - 1
          end
          # XXX The '?' was added ad-hoc to prevent exceptions when something goes out of
          # bounds (e.g. size of widget given too small for content).
          # Is there any better way to handle?
          lines[y]?.try(&.[x]?).try do |cell|
            if @track
              ch = @style.track.char # || ' '
              attr = sattr style.track, style.track.fg, style.track.bg
              screen.fill_region attr, ch, x, x + 1, yi, yl
            end
            ch = style.scrollbar.char # || ' '
            attr = sattr style.scrollbar, style.scrollbar.fg, style.scrollbar.bg
            if cell != {attr, ch}
              cell.attr = attr
              cell.char = ch
              lines[y]?.try &.dirty=(true)
            end
          end
        end
      end

      if @border
        xi -= 1
        xl += 1
        yi -= 1
        yl += 1
      end

      if @padding.any?
        xi -= @padding.left
        xl += @padding.right
        yi -= @padding.top
        yl += @padding.bottom
      end

      # Draw the border.
      if border = @border
        battr = sattr style.border
        y = yi
        if coords.no_top?
          y = -1
        end
        (xi...xl).each do |x|
          if (!lines[y]?)
            break
          end
          if coords.no_left? && (x == xi)
            next
          end
          if coords.no_right? && (x == xl - 1)
            next
          end
          cell = lines[y][x]?
          if (!cell)
            next
          end
          if border.type.line?
            if (x == xi)
              ch = '\u250c' # '┌'
              if (!border.left)
                if (border.top)
                  ch = '\u2500'
                  # '─'
                else
                  next
                end
              else
                if (!border.top)
                  ch = '\u2502'
                  # '│'
                end
              end
            elsif (x == xl - 1)
              ch = '\u2510' # '┐'
              if (!border.right)
                if (border.top)
                  ch = '\u2500'
                  # '─'
                else
                  next
                end
              else
                if (!border.top)
                  ch = '\u2502'
                  # '│'
                end
              end
            else
              ch = '\u2500'
              # '─'
            end
          elsif border.type.bg?
            ch = style.border.char
          end
          if (!border.top && x != xi && x != xl - 1)
            ch = ' '
            if cell != {dattr, ch}
              lines[y][x].attr = dattr
              lines[y][x].char = ch
              lines[y].dirty = true
              next
            end
          end
          if cell != {battr, ch}
            lines[y][x].attr = battr
            lines[y][x].char = ch ? ch : ' ' # XXX why ch can be nil?
            lines[y].dirty = true
          end
        end
        y = yi + 1
        while (y < yl - 1)
          if (!lines[y]?)
            break
          end
          cell = lines[y][xi]?
          if (cell)
            if (border.left)
              if border.type.line?
                ch = '\u2502'
                # '│'
              elsif border.type.bg?
                ch = style.border.char
              end
              if !coords.no_left?
                if cell != {battr, ch}
                  lines[y][xi].attr = battr
                  lines[y][xi].char = ch ? ch : ' '
                  lines[y].dirty = true
                end
              end
            else
              ch = ' '
              if cell != {dattr, ch}
                lines[y][xi].attr = dattr
                lines[y][xi].char = ch ? ch : ' '
                lines[y].dirty = true
              end
            end
          end
          cell = lines[y][xl - 1]?
          if (cell)
            if (border.right)
              if border.type.line?
                ch = '\u2502'
                # '│'
              elsif border.type.bg?
                ch = style.border.char
              end
              if !coords.no_right?
                if cell != {battr, ch}
                  lines[y][xl - 1].attr = battr
                  lines[y][xl - 1].char = ch ? ch : ' '
                  lines[y].dirty = true
                end
              end
            else
              ch = ' '
              if cell != {dattr, ch}
                lines[y][xl - 1].attr = dattr
                lines[y][xl - 1].char = ch ? ch : ' '
                lines[y].dirty = true
              end
            end
          end
          y += 1
        end
        y = yl - 1
        if coords.no_bottom?
          y = -1
        end
        (xi...xl).each do |x|
          if (!lines[y]?)
            break
          end
          if coords.no_left? && (x == xi)
            next
          end
          if coords.no_right? && (x == xl - 1)
            next
          end
          cell = lines[y][x]?
          if (!cell)
            next
          end
          if border.type.line?
            if (x == xi)
              ch = '\u2514' # '└'
              if (!border.left)
                if (border.bottom)
                  ch = '\u2500'
                  # '─'
                else
                  next
                end
              else
                if (!border.bottom)
                  ch = '\u2502'
                  # '│'
                end
              end
            elsif (x == xl - 1)
              ch = '\u2518' # '┘'
              if (!border.right)
                if (border.bottom)
                  ch = '\u2500'
                  # '─'
                else
                  next
                end
              else
                if (!border.bottom)
                  ch = '\u2502'
                  # '│'
                end
              end
            else
              ch = '\u2500'
              # '─'
            end
          elsif border.type.bg?
            ch = style.border.char
          end
          if (!border.bottom && x != xi && x != xl - 1)
            ch = ' '
            if cell != {dattr, ch}
              lines[y][x].attr = dattr
              lines[y][x].char = ch ? ch : ' '
              lines[y].dirty = true
            end
            next
          end
          if cell != {battr, ch}
            lines[y][x].attr = battr
            lines[y][x].char = ch ? ch : ' '
            lines[y].dirty = true
          end
        end
      end

      # Shadow
      if s = shadow
        if s.left?
          i = s.top? ? yi - 1 : yi
          l = s.bottom? ? yl + 1 : yl

          y = Math.max(i, 0)
          while (y < l)
            if (!lines[y]?)
              break
            end
            x = xi - 2
            while (x < xi)
              if (!lines[y][x]?)
                break
              end
              # D O:
              # lines[y][x].attr = Colors.blend(@dattr, lines[y][x].attr)
              lines[y][x].attr = Colors.blend(lines[y][x].attr, alpha: style.shadow_transparency)
              lines[y].dirty = true
              x += 1
            end
            y += 1
          end
        end

        if s.top?
          l = s.right? ? xl + 2 : (s.left? ? xl - 2 : xl)

          y = yi - 1
          while (y < yi)
            if (!lines[y]?)
              break
            end
            (Math.max(xi, 0)...(l)).each do |x2|
              if (!lines[y][x2]?)
                break
              end
              # D O:
              # lines[y][x].attr = Colors.blend(@dattr, lines[y][x].attr)
              lines[y][x2].attr = Colors.blend(lines[y][x2].attr, alpha: style.shadow_transparency)
              lines[y].dirty = true
            end
            y += 1
          end
        end

        if s.right?
          i = s.top? ? yi : yi + 1
          l = s.bottom? ? yl + 1 : yl

          y = Math.max(i, 0)
          while (y < l)
            if (!lines[y]?)
              break
            end
            x = xl
            while (x < xl + 2)
              if (!lines[y][x]?)
                break
              end
              # D O:
              # lines[y][x].attr = Colors.blend(@dattr, lines[y][x].attr)
              lines[y][x].attr = Colors.blend(lines[y][x].attr, alpha: style.shadow_transparency)
              lines[y].dirty = true
              x += 1
            end
            y += 1
          end
        end

        if s.bottom?
          i = s.right? ? xi + 1 : xi

          y = yl
          while (y < yl + 1)
            if (!lines[y]?)
              break
            end
            (Math.max(i, 0)...xl).each do |x2|
              if (!lines[y][x2]?)
                break
              end
              # D O:
              # lines[y][x].attr = Colors.blend(@dattr, lines[y][x].attr)
              lines[y][x2].attr = Colors.blend(lines[y][x2].attr, alpha: style.shadow_transparency)
              lines[y].dirty = true
            end
            y += 1
          end
        end
        # TODO Support for drawing left and top shadow
      end

      if with_children
        @children.each do |el|
          if el.screen._ci != -1
            el.index = el.screen._ci
            el.screen._ci += 1
          end

          el.render
        end
      end

      emit Crysterm::Event::Render # , coords

      coords
    end

    def render(with_children = true)
      _render with_children
    end

    def self.sattr(style : Style, fg = nil, bg = nil)
      if fg.nil? && bg.nil?
        fg = style.fg
        bg = style.bg
      end

      # TODO support style.* being Procs ?

      # D O:
      # return (this.uid << 24)
      #   | ((this.dockBorders ? 32 : 0) << 18)
      ((style.invisible ? 16 : 0) << 18) |
        ((style.inverse ? 8 : 0) << 18) |
        ((style.blink ? 4 : 0) << 18) |
        ((style.underline ? 2 : 0) << 18) |
        ((style.bold ? 1 : 0) << 18) |
        (Colors.convert(fg) << 9) |
        Colors.convert(bg)
    end

    def sattr(style : Style, fg = nil, bg = nil)
      self.class.sattr style, fg, bg
    end
  end
end
