# Copyright 2019 DragonRuby LLC
# MIT License
# console.rb has been released under MIT (*only this file*).

module GTK
  class Console
    attr_accessor :show_reason, :log, :prompt, :logo, :background_color,
                  :text_color, :cursor_color, :font, :animation_duration,
                  :max_log_lines, :max_history, :current_input_str, :log,
                  :last_command_errored, :last_command, :error_color, :shown_at,
                  :header_color, :archived_log, :last_log_lines, :last_log_lines_count,
                  :suppress_left_arrow_behavior

    def initialize
      @disabled = false
      @current_input_str = ''
      @log_offset = 0
      @visible = false
      @toast_ids = []
      @archived_log = []
      @log = [ 'Console ready.' ]
      @max_log_lines = 1000  # I guess...?
      @max_history = 1000  # I guess...?
      @command_history = []
      @command_history_index = -1
      @nonhistory_input = ''
      @prompt = '-> '
      @logo = 'console-logo.png'
      @history_fname = 'console_history.txt'
      @background_color = [ 0, 0, 0, 224 ]
      @text_color = [ 255, 255, 255, 255 ]
      @error_color = [ 200, 50, 50, 255]
      @header_color = [ 100, 200, 220, 255]
      @cursor_color = [ 187, 21, 6, 255 ]
      @font = 'font.ttf'
      @animation_duration = 1.seconds
      @current_input_str = ''
      @shown_at = -1
      load_history
    end

    def save_history
      str = ''
      @command_history.reverse_each { |s| str << s ; str << "\n" }
      $gtk.ffi_file.storefile(@history_fname, str)
    end

    def load_history
      @command_history.clear
      str = $gtk.ffi_file.loadfile(@history_fname)
      return if str.nil?  # no history to load.

      str.chomp!("\n")  # Don't let endlines at the end cause extra blank line.
      str.chomp!("\r")
      str.each_line { |s|
        s.chomp!("\n")
        s.chomp!("\r")
        if s.length > 0
          @command_history.unshift s
          break if @command_history.length >= @max_history
        end
      }
    end

    def disable
      @disabled = true
    end

    def enable
      @disabled = false
    end

    def console_text_width
      117
    end

    def addtext obj
      @last_log_lines_count ||= 1

      str = obj.to_s

      log_lines = []

      str.each_line { |s|
        s.wrapped_lines(console_text_width).each do |l|
          log_lines << l
        end
      }

      if log_lines == @last_log_lines
        @last_log_lines_count += 1
        new_log_line_with_count = @last_log_lines.last + " (#{@last_log_lines_count})"
        if log_lines.length > 1
          @log = @log[0..-(@log.length - log_lines.length)] + log_lines[0..-2] + [new_log_line_with_count]
        else
          @log = @log[0..-(@log.length - log_lines.length)] + [new_log_line_with_count]
        end
        return
      end

      log_lines.each do |l|
        @log.shift if @log.length > @max_log_lines
        @log << l
      end

      @last_log_lines_count = 1
      @last_log_lines = log_lines
    end

    def ready?
      visible? && @toggled_at.elapsed?(@animation_duration, Kernel.global_tick_count)
    end

    def hidden?
      !@visible
    end

    def visible?
      @visible
    end

    def show reason = nil
      @shown_at = Kernel.global_tick_count
      @show_reason = reason
      toggle if hidden?
    end

    def hide
      if visible?
        toggle
        @archived_log += @log
        if @archived_log.length > @max_log_lines
          @archived_log = @archived_log.drop(@archived_log.length - @max_log_lines)
        end
        @log.clear
        @show_reason = nil
        clear_toast
      end
    end

    def close
      hide
    end

    def clear_toast
      @toasted_at = nil
      @toast_duration = 0
    end

    def toggle
      @visible = !@visible
      @toggled_at = Kernel.global_tick_count
    end

    def currently_toasting?
      return false if hidden?
      return false unless @show_reason == :toast
      return false unless @toasted_at
      return false if @toasted_at.elapsed?(5.seconds, Kernel.global_tick_count)
      return true
    end

    def toast_extended id = nil, duration = nil, *messages
      if !id.is_a?(Symbol)
        raise <<-S
ERROR:
args.gtk.console.toast has the following signature:

  def toast id, *messages
  end

The id property uniquely defines the message and must be
a symbol.

After that, you can provide all the objects you want to
look at.

Example:

  args.gtk.console.toast :say_hello,
                            \"Hello world.\",
                            args.state.tick_count

Toast messages autohide after 5 seconds.

If you need to look at something for longer, use
args.gtk.console.perma_toast instead (which you can manually dismiss).

S
      end

      return if currently_toasting?
      return if @toast_ids.include? id
      @toasted_at = Kernel.global_tick_count
      log_once_info :perma_toast_tip, "Use console.perma_toast to show the toast for longer."
      dwim_duration = 5.seconds
      messages.each do |message|
        lines = message.to_s.wrapped_lines(console_text_width)
        dwim_duration += lines.length.seconds
        log message.to_s.wrap(console_text_width)
      end
      show :toast
      @toast_duration += duration || dwim_duration
      @toast_ids << id
    end

    def perma_toast id = nil, messages
      toast_extended id, 600.seconds, *messages
    end

    def toast id = nil, *messages
      toast_extended id, nil, *messages
    end

    def console_toggle_key_down? args
      return args.inputs.keyboard.key_down.backtick! ||
             args.inputs.keyboard.key_down.superscript_two! ||
             args.inputs.keyboard.key_down.section_sign! ||
             args.inputs.keyboard.key_down.ordinal_indicator!
    end

    def eval_the_set_command
      cmd = @current_input_str.strip
      if cmd.length != 0
        @log_offset = 0
        @current_input_str = ''

        @command_history.pop while @command_history.length >= @max_history
        @command_history.unshift cmd
        @command_history_index = -1
        @nonhistory_input = ''

        if cmd == 'quit' || cmd == ':wq' || cmd == ':q!' || cmd == ':q' || cmd == ':wqa'
          $gtk.request_quit
        else
          puts "-> #{cmd}"
          begin
            @last_command = cmd
            $gtk.ffi_mrb.eval("$results = (#{cmd})")
            if $results.nil?
              puts "=> nil"
            else
              puts "=> #{$results}"
            end
            @last_command_errored = false
          rescue Exception => e
            @last_command_errored = true
            puts "#{e}"
            log "#{e}"
          end
        end
      end
    end

    def process_inputs args
      if console_toggle_key_down? args
        args.inputs.text.clear
        toggle
      end

      return unless visible?

      if !@suppress_left_arrow_behavior && args.inputs.keyboard.key_down.left && (@current_input_str || '').strip.length > 0
        log_info "Use repl.rb!", <<-S
The Console is nice for quick commands, but for more complex edits, use repl.rb.

I've written the current command at the top of a file called ./repl.rb (right next to dragonruby(.exe)). Please open the the file and apply additional edits there.
S
        if @last_command_written_to_repl_rb != @current_input_str
          @last_command_written_to_repl_rb = @current_input_str
          contents = $gtk.read_file 'repl.rb'
          contents ||= ''
          contents = <<-S + contents

# Remove the x from xrepl to run the command.
xrepl do
  #{@last_command_written_to_repl_rb}
end

S
          $gtk.suppress_hotload = true
          $gtk.write_file 'repl.rb', contents
          $gtk.reload_if_needed 'repl.rb', true
          $gtk.suppress_hotload = false
        end

        return
      end

      args.inputs.text.each { |str| @current_input_str << str }
      args.inputs.text.clear

      if args.inputs.keyboard.key_down.enter
        eval_the_set_command
      elsif args.inputs.keyboard.key_down.v
        if args.inputs.keyboard.key_down.control || args.inputs.keyboard.key_down.meta
          @current_input_str << $gtk.ffi_misc.getclipboard
        end
      elsif args.inputs.keyboard.key_down.up
        if @command_history_index == -1
          @nonhistory_input = @current_input_str
        end
        if @command_history_index < (@command_history.length - 1)
          @command_history_index += 1
          @current_input_str = @command_history[@command_history_index].clone
        end
      elsif args.inputs.keyboard.key_down.down
        if @command_history_index == 0
          @command_history_index = -1
          @current_input_str = @nonhistory_input
          @nonhistory_input = ''
        elsif @command_history_index > 0
          @command_history_index -= 1
          @current_input_str = @command_history[@command_history_index].clone
        end
      elsif args.inputs.keyboard.key_down.pageup
        fontwidth, fontheight = $gtk.calcstringbox 'W', 1, @font   # we only need the height of a line of text here.
        lines_on_one_page = (720.0 / fontheight).to_i - 4
        @log_offset += lines_on_one_page
        @log_offset = @log.size if @log_offset > @log.size
      elsif args.inputs.keyboard.key_down.pagedown
        fontwidth, fontheight = $gtk.calcstringbox 'W', 1, @font   # we only need the height of a line of text here.
        lines_on_one_page = (720.0 / fontheight).to_i - 4
        @log_offset -= lines_on_one_page
        @log_offset = 0 if @log_offset < 0
      elsif args.inputs.keyboard.key_down.escape
        @current_input_str.clear
        @command_history_index = -1
        @nonhistory_input = ''
      elsif args.inputs.keyboard.key_down.backspace || args.inputs.keyboard.key_down.delete
        @current_input_str.chop!
      end

      args.inputs.keyboard.key_down.clear
      args.inputs.keyboard.key_up.clear
      args.inputs.keyboard.key_held.clear
    end

    def write_line args, left, y, str, errorinfo, headerinfo, txtinfo
      str ||= ''
      if include_error_marker? str
        args.outputs.reserved << [left + 10, y, str, 1, 0, *errorinfo].label
      elsif include_subdued_markers? str
        args.outputs.reserved << [left + 10, y, str, 1, 0, [txtinfo[0..2], txtinfo[3].half]].label
      elsif str.start_with?("====") || str.include?("app")
        args.outputs.reserved << [left + 10, y, str, 1, 0, *headerinfo].label
      else
        args.outputs.reserved << [left + 10, y, str, 1, 0, *txtinfo].label
      end
    end

    def render args
      return if !@toggled_at

      if visible?
        percent = @toggled_at.ease_using_global_tick_count(@animation_duration, :flip, :quint, :flip)
      else
        percent = @toggled_at.ease_using_global_tick_count(@animation_duration, :flip, :quint)
      end

      return if percent == 0

      w, h = $gtk.calcstringbox 'W', 1, @font   # we only need the height of a line of text here.

      top = $gtk.args.grid.top
      left = $gtk.args.grid.left
      y = top - (720.0 * percent)
      args.outputs.reserved << [left, y, 1280, 720, @background_color[0], @background_color[1], @background_color[2], (@background_color[3].to_f * percent).to_i].solid

      logo_y = y

      txtinfo = [ @text_color[0], @text_color[1], @text_color[2], (@text_color[3].to_f * percent).to_i, @font ]
      errorinfo = [ @error_color[0], @error_color[1], @error_color[2], (@error_color[3].to_f * percent).to_i, @font ]
      cursorinfo = [ @cursor_color[0], @cursor_color[1], @cursor_color[2], (@cursor_color[3].to_f  * percent).to_i, @font ]
      headerinfo = [  @header_color[0], @header_color[1], @header_color[2], (@header_color[3].to_f  * percent).to_i, @font ]

      y += 2  # just give us a little padding at the bottom.
      y += h  # !!! FIXME: remove this when we fix coordinate origin on labels.
      args.outputs.reserved << [left + 1280 - 210, logo_y + 540, 200, 200, @logo, 0, (80.0 * percent).to_i].sprite
      args.outputs.reserved << [left + 10, y, "#{@prompt}#{@current_input_str}", 1, 0, *txtinfo].label
      args.outputs.reserved << [left + 8, y + 3, (" " * (prompt.length + @current_input_str.length)) + "|", 1, 0, *cursorinfo ].label
      y += h.to_f / 2.0
      args.outputs.reserved << [left + 0, y, 1280, y, *txtinfo].line
      y += h.to_f / 2.0
      y += h  # !!! FIXME: remove this when we fix coordinate origin on labels.

      ((@log.size - @log_offset) - 1).downto(0) do |idx|
        write_line args, left, y, @log[idx], errorinfo, headerinfo, txtinfo
        y += h
        break if y > top
      end

      # past log seperator
      args.outputs.reserved << [0, y - h.half, 1280, y - h.half, [txtinfo[0..2], txtinfo[3].idiv(4)]].line

      y += h

      txtinfo = [ @text_color[0], @text_color[1], @text_color[2], (@text_color[3].to_f * percent.half).to_i, @font ]
      errorinfo = [ @error_color[0], @error_color[1], @error_color[2], (@error_color[3].to_f * percent.half).to_i, @font ]
      cursorinfo = [ @cursor_color[0], @cursor_color[1], @cursor_color[2], (@cursor_color[3].to_f  * percent.half).to_i, @font ]
      headerinfo = [  @header_color[0], @header_color[1], @header_color[2], (@header_color[3].to_f  * percent.half).to_i, @font ]

      ((@archived_log.size - @log_offset) - 1).downto(0) do |idx|
        write_line args, left, y, @archived_log[idx], errorinfo, headerinfo, txtinfo
        y += h
        break if y > top
      end
    end

    def include_error_marker? text
      include_any_words? text, error_markers
    end

    def error_markers
      ["exception", "error", "undefined method", "failed", "syntax", "deprecated"]
    end

    def include_subdued_markers? text
      include_any_words? text, subdued_markers
    end

    def include_any_words? text, words
      words.any? { |w| text.downcase.include? w }
    end

    def subdued_markers
      ["reloaded", "exported the"]
    end

    def calc args
      if visible? &&
         @show_reason == :toast &&
         @toasted_at &&
         @toasted_at.elapsed?(@toast_duration, Kernel.global_tick_count)
        hide
      end

      if !$gtk.paused? && visible? && show_reason == :exception
        hide
      end

      if $gtk.files_reloaded.length > 0
        clear_toast
        @toast_ids.clear
      end
    end

    def tick args
      begin
        return if @disabled
        render args
        calc args
        process_inputs args
      rescue Exception => e
        @disabled = true
        $stdout.puts e
        $stdout.puts "The GTK::Console console threw an unhandled exception and has been reset. You should report this exception (along with reproduction steps) to DragonRuby."
      end
    end

    def set_command command, show_reason = nil
      @command_history << command
      @current_input_str = command
      show show_reason
    end
  end
end
