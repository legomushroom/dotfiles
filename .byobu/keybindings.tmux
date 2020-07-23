unbind-key -n C-a
unbind-key -n C-z
unbind-key -n C-s
set -g prefix ^S
set -g prefix2 F12
bind s send-prefix
bind-key -n M-l select-pane -R
bind-key -n M-h select-pane -L
bind-key -n M-L resize-pane -R 1
bind-key -n M-H resize-pane -L 1
bind-key -n M-J resize-pane -D 1
bind-key -n M-K resize-pane -U 1
bind-key -n M-j select-pane -D
bind-key -n M-k select-pane -U
