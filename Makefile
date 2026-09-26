# Mac/Linux convenience targets (Windows: use npm scripts)
.PHONY: setup dev api web

setup:
	npm run setup

dev:
	npm run dev

api:
	npm run dev:api

web:
	npm run dev:web
