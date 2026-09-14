# 仅针对 WindTerm 细粒度拦截 systemd OSC 3008 上下文转义序列（避免提示符乱码）
if [ "$TERM_PROGRAM" = "WindTerm" ] || [ -n "$WINDTERM_SESSION" ]; then
    __systemd_osc_context_precmdline() { :; }
    __systemd_osc_context_ps0() { :; }
    unset systemd_osc_context_cmd_id systemd_osc_context_shell_id
    PS0=""
fi
