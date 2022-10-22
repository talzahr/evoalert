# Evocati Alert Script for New Build Notification

This script is meant for Star Citizen Evocati testers to know when a new build is ready. 

Checking the MOTD can be anoying at times. So why not automate this? Calling the GetMOTD JSON from Spectrum is very cumbersome and requires multiple steps, done in order, while logged into Spectrum. That method was not very good. Unfortunately, soon after a new NDA patch note is published, it is leaked to the public within minutes. While I completely disapprove of not respecting the NDA, it is convenient for the purposes of this alert BASH script. 


## What this Script Does

On a configured timed loop, the script will retreive the Pastebin user index page of an egregious patch note leaker. When it sees a post title referring to *Evocati*, the paste key is compared with recorded keys. If there is not a match, then the user is alerted by audio file and STDOUT message. The option to read the raw patch note is also made available. 


## How to Install

Simply git clone this repo and run the shell script as any other outside of the system path, with `./evoalert.sh`

The script is configured to run directly from a user's home tree. However, just change the config variables at the head of the script to change locations of the audio file and log if, say, you want to install it into /usr/local/bin. At a later date I may include a setup and install script. 


## How to Use

First, look over the configuration variables at the head of the `evoalert.sh` file, at the very least the `general` and `audio` sections. You'll need to provide your own audio file and insert its location into the `audioFile` variable. I can't include the one I use due to distribution license restrictions. 

Then run `./evoalert.sh`. For now you have to SIGINT (ctrl-c) out of the main loop to exit script. 

**For Cygwin64 users**: This was tested in Cygwin on Windows 10 and works fine. However, you may want to increase the priority of the `Windows Command Processor` that Cygwin uses to a level of at least **high**. Otherwise Windows may cause the main loop to freeze if it dedicates system resources away. 


## License

MIT License, [see LICENSE](../master/LICENSE).


## TO DO

-A open license audio file
-User-customizable colors
-Maybe a install and config script for the important options
-More ANSI escape sequences, because they're great 
-Main loop in its own subshell so the user can input keys while it runs and change settings realtime

Simple script so didn't add too much. Just fun to do. 


