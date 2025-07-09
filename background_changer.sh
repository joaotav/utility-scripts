#!/bin/bash

# Diretório onde estão as imagens
DIR="/home/user/Pictures/"

# Comando que seleciona aleatoriamente um arquivo .jpg ou .png
PIC=$(ls $DIR/*.jpg $DIR/*.png | shuf -n1)

# Comando que define a tela de fundo
gsettings set org.gnome.desktop.background picture-uri "file:"$PIC



