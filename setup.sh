#!/usr/bin/env bash

rm -rf test/



read -r -p "Enter project name: " project_name < /dev/tty
mkdir "$project_name" || exit

PROJECT_DIR="$PWD/$project_name"

echo "Creating a gotth project, $project_name { $PROJECT_DIR }"

cd "$PROJECT_DIR" || { echo "$PROJECT_DIR not created"; exit; }

mkdir cmd pkg static tmp
mkdir "$PROJECT_DIR"/static/{js,css,imgs}

touch cmd/main.go
touch Makefile


go version > /dev/null || { echo "Go not found"; exit; }

read -r -p "Enter module path: " module_path < /dev/tty

go mod init "$module_path" 2> /dev/null || { echo "Error while go mod init"; exit; }

# Locate and load NVM across standard path locations
if ! command -v npm &> /dev/null; then
    # Try standard user home path
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        . "$NVM_DIR/nvm.sh"
    elif [ -s "$HOME/.nvm/nvm.sh" ]; then
        . "$HOME/.nvm/nvm.sh"
    elif [ -s "/usr/local/share/nvm/nvm.sh" ]; then
        . "/usr/local/share/nvm/nvm.sh"
    fi
fi

# Fallback: manually export the node/npm binary path from active environment if NVM script isn't found
if ! command -v npm &> /dev/null; then
    NODE_BIN_PATH=$(dirname "$(which node 2>/dev/null)")
    [ -n "$NODE_BIN_PATH" ] && export PATH="$PATH:$NODE_BIN_PATH"
fi
npm --version > /dev/null || { echo "npm not found"; exit 1; }
npm init -y > /dev/null || { echo "npm init failed"; exit; }
npm install -D tailwindcss @tailwindcss/cli > /dev/null || { echo "error installing tailwindcss"; }

echo "/** @type {import('tailwindcss').Config} */
export default {
  content: [\"./pkg/view/**/*.templ\"],
  theme: {
    extend: {}
  },
  plugins: [],
}" > "$PROJECT_DIR/tailwind.config.js"

echo "@import \"tailwindcss\";" > "$PROJECT_DIR"/static/css/input.css

mkdir -p "$PROJECT_DIR"/pkg/{views,utils}

echo "package views

import \"$module_path/pkg/views/layout\"

templ Home() {
	@views.BaseLayout() {
		<div class=\"w-full h-max flex flex-col items-center text-blue-500\">
            Hell 'o' World
		</div>
	}
}" > "$PROJECT_DIR"/pkg/views/home.templ

mkdir "$PROJECT_DIR/pkg/views/layout"

echo "package views

templ BaseLayout() {
	<!DOCTYPE html>
	<html>
		<head>
			<meta charset=\"UTF-8\"/>
			<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\"/>
			<title>ENTER TITLE</title>
			<script src=\"https://cdn.jsdelivr.net/npm/htmx.org@2.0.8/dist/htmx.min.js\"></script>
			<link href=\"/static/css/tailwind.css\" rel=\"stylesheet\"/>
		</head>
		<body class=\"bg-slate-600 text-slate-200\">
			{ children... }
		</body>
	</html>
}" > "$PROJECT_DIR/pkg/views/layout/base.templ"

echo "package utils

import (
	\"fmt\"
	\"log/slog\"
	\"os\"
)

func NewLogger(logFilePath string) (*slog.Logger, func() error, error) {
	logFile, err := os.OpenFile(logFilePath, os.O_APPEND|os.O_WRONLY|os.O_CREATE, 0666)

	if err != nil {
		return nil, nil, fmt.Errorf("open log file %s: %w", logFilePath, err)
	}

	return slog.New(slog.NewTextHandler(logFile, nil)), logFile.Close, nil
}" > "$PROJECT_DIR"/pkg/utils/base.go


echo "package main

import (
    \"net/http\"
    \"fmt\"
    \"$module_path/pkg/utils\"
    \"$module_path/pkg/views\"
    \"log/slog\"
    \"context\"
)

type Server struct {
	mux    *http.ServeMux
	port   uint16
	id     string
	logger *slog.Logger
}

func (s *Server) String() string {
	return fmt.Sprintf(\"[{port: %d}-{id: %s}]\", s.port, s.id)
}

func (s *Server) Start() error {
	err := http.ListenAndServe(fmt.Sprintf(\":%d\", s.port), s.mux)
	if err != nil {
		return err
	}
	return nil
}

func ConfigureServer(port uint16, id string, logger *slog.Logger) (*Server, error) {
	mux := http.NewServeMux()

	server := &Server{
		mux:    mux,
		port:   port,
		id:     id,
		logger: logger,
	}

	fs := http.FileServer(http.Dir(\"./static\"))

	mux.Handle(\"GET /static/\", http.StripPrefix(\"/static/\", fs))

	mux.HandleFunc(\"GET /\", func(w http.ResponseWriter, r *http.Request) {
        if err := views.Home().Render(r.Context(), w); err != nil {
			logger.ErrorContext(r.Context(), "render home", "error", err)
			http.Error(w, "internal server error", http.StatusInternalServerError)
        }
	})

	return server, nil
}

func run() error {
	logger, closer, err := utils.NewLogger("logs.log") // This returns a logger, do use it if you feel like.
	defer closer()

	server, err := ConfigureServer(5301, "dev.bundler.test", logger)
	if err != nil {
		return err
	}

	if err := server.Start(); err != nil {
		return err
	}
	
	return nil
}


func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "babylon:", err)
		os.Exit(1)
	}
}" > "$PROJECT_DIR/cmd/main.go"


echo "build:
	mkdir -p tmp/ && rm -rf tmp/* && go build -o tmp/main ./cmd 

format:
	gofmt -w .

generate_templates:
	templ generate

run: format generate_templates build
	./tmp/main

tailwatch:
	npx @tailwindcss/cli -i ./static/css/input.css -o ./static/css/tailwind.css --watch
" > "$PROJECT_DIR"/Makefile


echo "#:schema https://json.schemastore.org/any.json

root = \".\"
testdata_dir = \"testdata\"
tmp_dir = \"tmp\"

[build]
  args_bin = []
  bin = \"./tmp/main\"
  cmd = \"templ generate && go build -o tmp/main cmd/main.go\"
  delay = 1000
  entrypoint = [\"./tmp/main\"]
  exclude_dir = [\"static\", \"node_modules\", \"assets\", \"tmp\", \"vendor\", \"testdata\"]
  exclude_file = []
  exclude_regex = [\"_test.go\", \"_templ.go\"]
  exclude_unchanged = false
  follow_symlink = false
  full_bin = \"\"
  include_dir = []
  include_ext = [\"go\", \"tpl\", \"tmpl\", \"html\", \"templ\"]
  include_file = []
  kill_delay = \"0s\"
  log = \"build-errors.log\"
  poll = false
  poll_interval = 0
  post_cmd = []
  pre_cmd = []
  rerun = false
  rerun_delay = 500
  send_interrupt = false
  stop_on_error = false

[color]
  app = \"\"
  build = \"yellow\"
  main = \"magenta\"
  runner = \"green\"
  watcher = \"cyan\"

[log]
  main_only = false
  silent = false
  time = false

[misc]
  clean_on_exit = true

[proxy]
  app_port = 0
  enabled = false
  proxy_port = 0

[screen]
  clear_on_rebuild = false
  keep_scroll = true" > "$PROJECT_DIR"/.air.toml

npx @tailwindcss/cli -i ./static/css/input.css -o ./static/css/tailwind.css

go get github.com/a-h/templ@latest
templ generate
go mod tidy

