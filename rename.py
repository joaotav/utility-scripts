# -*- coding: utf-8 -*-

import os
os.system("ls >> items.txt")

incremento = 1
nome = "imagem" # name that will be given to the files


with open("items.txt", "r") as arquivos:
    dados = arquivos.readlines()
    for arquivo in dados:
        if ".jpg" in arquivo: # If it's a jpg file, use .jpg extension
            os.system("mv {} {}{}{}".format(arquivo.rstrip('\n'), nome, str(incremento), ".jpg"))
        elif ".png" in arquivo: # If it's a png file, use .png extension
            os.system("mv {} {}{}{}".format(arquivo.rstrip('\n'), nome, str(incremento), ".png"))
        incremento += 1

os.system("rm items.txt") # Deletes the file containing the filenames
