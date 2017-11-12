#!/bin/sh

#Download splash and 00-header file for motd (message of the day)
wget $1
wget $2

sudo rm -rf /etc/update-motd.d/*
sudo cp ./assurity.splash /etc/update-motd.d/
sudo cp ./00-header /etc/update-motd.d/
sudo chmod +x /etc/update-motd.d/00-header
