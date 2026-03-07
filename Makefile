# Makefile for clash-for-linux
# 快捷命令入口

CMD := scripts/cmd

.PHONY: check install up down logs status

check:
	@bash check-deps.sh

install:
	@sudo bash $(CMD)/service-install.sh

up:
	@bash $(CMD)/service-start.sh

down:
	@bash $(CMD)/service-stop.sh

logs:
	@./clashctl status

status:
	@./clashctl status
