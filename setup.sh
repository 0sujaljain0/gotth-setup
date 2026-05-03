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

npm --version > /dev/null || { echo "npm not found"; exit; }
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

func NewLogger(logFilePath string) (*slog.Logger, func()) {
	logFile, err := os.OpenFile(logFilePath, os.O_APPEND|os.O_WRONLY|os.O_CREATE, 0666)
	closeFunc := func() {
		err := logFile.Close()
		if err != nil {
			panic(fmt.Errorf(\"while closing the file: %+v\", err))
		}
	}

	if err != nil {
		panic(fmt.Sprintf(\"log file not initialized: %s\", err))
	}

	return slog.New(slog.NewTextHandler(logFile, nil)), closeFunc
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
		err := views.Home().Render(context.Background(), w)
		if err != nil {
			panic(err)
		}
	})

	return server, nil
}

func main() {
	logger, closer := utils.NewLogger(\"logs.log\") // This returns a logger, do use it if you feel like.
	defer closer()
	server, err := ConfigureServer(8080, \"dev.bundler.test\", logger)
	if err != nil {
		panic(err)
	}

	if err := server.Start(); err != nil {
		panic(err)
	}
}" > "$PROJECT_DIR/cmd/main.go"


echo "build:
	mkdir -p tmp/ && rm -rf tmp/* &&  go build -o tmp/main cmd/main.go 

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

go get github.com/a-h/templ@latest
templ generate
go mod tidy
