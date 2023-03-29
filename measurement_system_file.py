import RPi.GPIO as GPIO
import csv
import serial
import os.path
import sys
import requests
from requests.adapters import HTTPAdapter
import json
import msal
import psutil
import time
from time import perf_counter 
from datetime import datetime
import threading
from threading import Thread
import os
import tkinter as tk
from tkinter import *
from tkinter.ttk import *
from tkinter import filedialog


ser = serial.Serial('/dev/ttyS0',115200)
ser.flushInput()
path = '/home/rpi/Desktop/Measurement Files'
power_key = 6
rec_buff = ''

downloadUrl = 'https://freetestdata.com/wp-content/uploads/2021/09/Free_Test_Data_1MB_PDF.pdf'
website_adapter = HTTPAdapter(max_retries=3)
session = requests.Session()
session.mount(downloadUrl, website_adapter)

#Updates real time measurment display
def display(GPSline,Signalline,Dataline):
    with open('temp.txt', 'w') as temp_file:
        GPSTag = GPSline.split(':')
        GPS = GPSTag[1]
        splitGPS = GPS.split(',')
        if len(splitGPS) <= 6:
            ASTtime = 0
            FinalLat = 0
            FinalLong = 0
            speed = 0
            
        elif len(splitGPS)> 6:
            Latitude=splitGPS[0]
            Latline = Latitude[:2]
            SmallLat = Latitude[2:9]
            NorthOrSouth = splitGPS[1]

            Longitude = splitGPS[2]
            Longline = Longitude[:3]
            SmallLong = Longitude[3:9]
            EastOrWest = splitGPS[3]                                      

            FinalLat = float(Latline) + (float(SmallLat)/60)
            FinalLong = float(Longline) + (float(SmallLong)/60)
                                            
            if NorthOrSouth == 'S': FinalLat = -FinalLat
            if EastOrWest == 'W': FinalLong = -FinalLong

            #Speed/Velocity
            speedKnots = splitGPS[7]
            speed = float(speedKnots) * 0.51444

            #Time
            UTCtime = float(splitGPS[5])
            ASTtime = 0
            rem = 0
            if UTCtime >= 40000:
                ASTtime = UTCtime - 40000  #converting to atlantic standard time
                if ASTtime < 100000:
                    temp_string = str(ASTtime)
                    ASTtime = "0"+ temp_string
            else: 
                rem = 40000 - UTCtime
                ASTtime = 240000 - rem

        signalTag = Signalline.split(':')
        signal = signalTag[1]
        splitSignal = signal.split(',')
        if len(splitSignal)>12: 
            PCI = splitSignal[5]
                        
            band_name = splitSignal[6]
            split_band_name = band_name.split('D')
            Band = split_band_name[1]

            EARFCN = splitSignal[7]

            RSRQ = float(splitSignal[10])

            RSRP = float(splitSignal[11])*0.1

            RSSI = float(splitSignal[12])*0.1

            RSSNR = float(splitSignal[13])
    
        #Data Line
        dataTag = Dataline.split('+Data:')
        data = dataTag[1]
        splitData = data.split(',')
        if len(splitData)>3:
            DataTime = splitData[0]
                        
            NewBytes = splitData[1]
                        
            TotalBytes = splitData[2]
                        
            Throughput = splitData[3]
        
        newline = f"{ASTtime},{FinalLat: .5f}, {FinalLong: .5f}, {speed: .2f},{PCI}, {Band}, {EARFCN}, {RSRQ: .2f}, {RSRP: .2f}, {RSSI: .2f}, {RSSNR: .2f}, {Throughput}, {NewBytes}"
        print(newline)
        writer = csv.writer(temp_file)
        writer.writerow([newline])
        temp_file.close()

#Powers on LTE HAT
def power_on(power_key):
	print('SIM7600X is starting:')
	GPIO.setmode(GPIO.BCM)
	GPIO.setwarnings(False)
	GPIO.setup(power_key,GPIO.OUT)
	time.sleep(0.1)
	GPIO.output(power_key,GPIO.HIGH)
	time.sleep(2)
	GPIO.output(power_key,GPIO.LOW)
	time.sleep(20)
	ser.flushInput()
	print('SIM7600X is ready')

#Powers off LTE HAT
def power_down(power_key):
	print('SIM7600X is loging off:')
	GPIO.output(power_key,GPIO.HIGH)
	time.sleep(3)
	GPIO.output(power_key,GPIO.LOW)
	time.sleep(18)
	print('Good bye')

#Encodes AT-command and send the command to the LTE HAT
def send_at(command,back,timeout):
	rec_buff = ''
	ser.write((command+'\r\n').encode())
	time.sleep(timeout)
	if ser.inWaiting():
		time.sleep(0.01 )
		rec_buff = ser.read(ser.inWaiting())
	if rec_buff != '':
		rawdata = rec_buff.decode()
		if back not in rawdata:
			print(command + ' ERROR')
			print(command + ' back:\t' + rawdata)
			return 0
		else:
			splitdata = rawdata.split()
			data = splitdata[0] + splitdata[1]
			print(data)
			return 1,data
	else:
		print('GPS is not ready...still configuring')
		return 0

#Measures the number of bytes received in 0.25 seconds and calculates the goodput(Throughput) in bps
def measure_data():
    last_received = psutil.net_io_counters().bytes_recv
    now = datetime.now()
    current_time = now.strftime("%H:%M:%S")
    time.sleep(0.25)
    bytes_received = psutil.net_io_counters().bytes_recv
    new_received = bytes_received - last_received
    Throughput = (new_received*8)/0.25
    line = f"+Data:{current_time},{new_received: .2f},{bytes_received: .2f}, {Throughput: .2f}"
    print(line)
    return line

# Downloads a test file from a website 
def get_file():
    try:
        with open ('input_time.txt','r') as f:
            runTime = f.read()
            t_end = time.time()  + int(runTime)
        while time.time() < t_end:
            start_time = time.time()
            req = session.get(downloadUrl)
            filename = req.url[downloadUrl.rfind('/')+1:]
            with open(filename, 'wb') as f: 
                f.write(req.content) 
    except ConnectionError as ce:
        print(ce)

# Queries the signal and data parameters for the duration of the while loop 
def get_parameters(): 
	rec_null = True
	answer = 0
	print('Start GPS session...')
	rec_buff = ''
	send_at('AT+CGPS=1,1','OK',0.25)
	time.sleep(2)
	with open ('input_time.txt','r') as f:
		runTime = f.read()
		print (runTime)
	t_end = time.time()  + int(runTime)
	with open (file, 'w') as f:
		writer = csv.writer(f) 
		while time.time() < t_end and not stop_measure:
			answer,GPSline = send_at('AT+CGPSINFO','+CGPSINFO: ',0.25)
			writer.writerow([GPSline])
			answer,Signalline = send_at('AT+CPSI?','+CPSI: ',0.25)
			writer.writerow([Signalline])
			dataLine = measure_data()
			writer.writerow([dataLine])
			display(GPSline,Signalline,dataLine)
			if 1 == answer:
				answer = 0
				if ',,,,,,' in rec_buff:
					print('GPS configuring')
					rec_null = False
					time.sleep(1)
			else:
				print('error %d'%answer)
				rec_buff = ''
				send_at('AT+CGPS=0','OK',0.25)
				return False
				time.sleep(0.001)

#Deletes the measurmeent file
def delete_file():
    if os.path.exists(file):
      os.remove(file)
      print(f"{measurement_filename} was deleted")
    else:
      print("The file does not exist")

#Saves the measurement file to the default folder or new destination selected from the dialogue box
def save_file():
    current_file = filedialog.asksaveasfile(initialdir=path,
                                    initialfile=measurement_filename,
                                    defaultextension='.txt',
                                    filetypes=[
                                        ("Text file",".txt"),
                                        ("All files", ".*"),
                                    ])
    print("File saved")
    cloud_export()
    if current_file is None:
        return

#Second UI window allowing the user to choose to save or delete the measurment file
def new_window():
        parent = tk.Tk()
        frame = tk.Frame(parent)
        frame.pack()

        exit_button= tk.Button(frame, 
                           text="Save", 
                           fg="green",
                           command=save_file
                           )

        exit_button.pack(side=tk.LEFT)

        text_disp = tk.Button(frame,
                           text="Delete",
                           fg="red",
                           command=delete_file)
        text_disp.pack(side=tk.RIGHT)

#Uploads the measurmeent file to a destination folder on One Drive
def cloud_export():
    CLIENT_ID = '81d57aa5-5e0e-470b-8b37-a69efe48288a'
    TENANT_ID = 'aae862ee-56a9-48cb-ac59-11922bb9b864'
    AUTHORITY_URL = 'https://login.microsoftonline.com/{}'.format(TENANT_ID)
    RESOURCE_URL = 'https://graph.microsoft.com/'
    API_VERSION = 'v1.0'
    USERNAME = 'hayley.gittens@my.uwi.edu' #Office365 user's account username
    PASSWORD = '********'
    SCOPES = ['Sites.ReadWrite.All','Files.ReadWrite.All'] # Add other scopes/permissions as needed.

    #Creating a public client app, acquires a access token for the user and set the header for API calls
    pi_to_onedrive = msal.PublicClientApplication(CLIENT_ID, authority=AUTHORITY_URL)
    token = pi_to_onedrive.acquire_token_by_username_password(USERNAME,PASSWORD,SCOPES)
    headers = {'Authorization': 'Bearer {}'.format(token['access_token'])}
    onedrive_destination = '{}{}/me/drive/root:/RPi Measurements'.format(RESOURCE_URL,API_VERSION)
    rpi_source = r"/home/rpi/Desktop/Measurement Files"

    #Looping through the files inside the source directory
    for root, dirs, files in os.walk(rpi_source):
        for file_name in files:
            file_path = os.path.join(root,file_name)
            if file_path == file:
                file_data = open(file_path, 'rb')
                #Perform is simple upload to the API
                r = requests.put(onedrive_destination+"/"+file_name+":/content", data=file_data, headers=headers)
                print('File uploaded to cloud')
                
class MeasurementDisplay:
    def __init__(self):
        self.root = tk.Tk()
        self.root.geometry("520x420")
        self.root.title("RPi Based LTE Measurement System")
        

        self.timing_label = tk.Label(self.root,  text='Time: ', width = 12, anchor='w' )  
        self.timing_label.grid(row=4,column=1,padx=30)

        self.loc_label = tk.Label(self.root,  text='Location: ', width = 12, anchor='w' )  
        self.loc_label.grid(row=5,column=1)

        self.vel_label = tk.Label(self.root,  text='Speed (m/s): ', width = 12, anchor='w' ) 
        self.vel_label.grid(row=7,column=1)
        
        self.PCI_label = tk.Label(self.root,  text='PCI: ', width = 12, anchor='w' ) 
        self.PCI_label.grid(row=8,column=1) 
        
        self.Band_label = tk.Label(self.root,  text='Band: ', width = 12, anchor='w') 
        self.Band_label.grid(row=9,column=1) 

        self.EARFCN_label = tk.Label(self.root,  text='EARFCN: ', width = 12, anchor='w' ) # added one Label 
        self.EARFCN_label.grid(row=10,column=1) 
        
        self.RSRQ_label = tk.Label(self.root,  text='RSRQ (dBm): ', width = 12, anchor='w' ) # added one Label 
        self.RSRQ_label.grid(row=11,column=1) 

        self.RSRP_label = tk.Label(self.root,  text='RSRP (dBm): ', width = 12, anchor='w' ) # added one Label 
        self.RSRP_label.grid(row=12,column=1) 

        self.RSSI_label = tk.Label(self.root,  text='RSSI (dBm): ', width = 12, anchor='w' ) # added one Label 
        self.RSSI_label.grid(row=13,column=1) 

        self.RSSNR_label = tk.Label(self.root,  text='RSSNR (dB): ', width = 12, anchor='w' ) # added one Label 
        self.RSSNR_label.grid(row=14,column=1) 

        self.Tput_label = tk.Label(self.root,  text='Throughput (bps): ', width = 12, anchor='w' ) # added one Label 
        self.Tput_label.grid(row=15,column=1) 

        self.byte_label = tk.Label(self.root,  text='Bytes: ', width = 12, anchor='w') # added one Label 
        self.byte_label.grid(row=16,column=1) 

        self.time_entry = tk.Entry(self.root, font=("Helvetica", 15))
        self.time_entry.grid(row=1, column=2, columnspan=3, padx=5, pady=5)

        self.start_button = tk.Button(self.root, font=("Helvetica", 15), text="Start", command=self.start_thread)
        self.start_button.grid(row=2, column=2, padx=5, pady=5)

        self.stop_button = tk.Button(self.root, font=("Helvetica", 15), text="Stop", command=self.stop)
        self.stop_button.grid(row=2, column=3, padx=5, pady=5)

        self.time_label = tk.Label(self.root, font=("Helvetica", 15), text="Duration: 00:00:00")
        self.time_label.grid(row=3, column=3, padx=5, pady=5)

        self.quit_button = tk.Button(self.root, font=("Helvetica", 15), text="Quit", command=self.quit_thread)#command=self.measurement_thread)
        self.quit_button.grid(row=2, column=4, padx=5, pady=5)

        self.stop_loop = False

        self.root.mainloop()

    def start_thread(self):
        t = threading.Thread(target=self.start,args= [])
        p = threading.Thread(target=get_parameters,args = [])
        g = threading.Thread(target=get_file,args = [])
        t.start()
        p.start()
        time.sleep(1)
        g.start()
        
    def start(self):
        global stop_measure
        stop_measure = False
        self.stop_loop = False
        hours,minutes,seconds=0,0,0
        string_split = self.time_entry.get().split(":")
        if len(string_split) == 3:
            hours = int(string_split[0])
            minutes = int(string_split[1])
            seconds = int(string_split[2])

        elif len(string_split) == 2:
            minutes = int(string_split[0])
            seconds = int(string_split[1])

        elif len(string_split) == 1:
            seconds = int(string_split[0])

        else:
            print("Invalid time format")
            return
        full_seconds = (hours*3600) + (minutes * 60) + seconds
        with open('input_time.txt', 'w') as f:
            f.write(str(full_seconds))
        while full_seconds > 0 and not self.stop_loop:
            full_seconds -= 1

            minutes, seconds = divmod(full_seconds, 60)
            hours, minutes = divmod(minutes, 60)
            self.time_label.config(text=f"Time: {hours:02d}:{minutes:02d}:{seconds:02d}")
            
            with open('temp.txt', 'r') as temp:
                if os.stat('temp.txt').st_size == 0:
                    timing = '-'
                    latitude = '-'
                    longitude = '-'
                    speed = '-'
                    PCI = '-'
                    Band = '-'
                    EARFCN = '-'
                    RSRQ = '-'
                    RSRP = '-'
                    RSSI = '-'
                    RSSNR = '-'
                    Throughput = '-'
                    Bytes = '-'
                    
                else:   
                    parameter_line = str(temp.readlines())
                    if parameter_line != '':
                        split_line= parameter_line.split(',')
                        front = split_line[0]
                        timing = front[3:]
                        latitude = split_line[1]
                        longitude = split_line[2]
                        speed = split_line[3]
                        PCI = split_line[4]
                        Band = split_line[5]
                        EARFCN = split_line[6]
                        RSRQ = split_line[7]
                        RSRP = split_line[8]
                        RSSI = split_line[9]
                        RSSNR = split_line[10]
                        Throughput = split_line[11]
                        end = split_line[12]
                        Bytes = end[:-5]
                
            self.timing_label.config(text=f"Time:{timing}")
            self.loc_label.config(text=f"Location:{latitude},{longitude}")
            self.vel_label.config(text=f"Speed(m/s):{speed}")
            self.PCI_label.config(text=f"PCI:{PCI}")
            self.Band_label.config(text=f"Band:{Band}")
            self.EARFCN_label.config(text=f"EARFCN:{EARFCN}")
            self.RSRQ_label.config(text=f"RSRQ(dBm):{RSRQ}")
            self.RSRP_label.config(text=f"RSRP(dBm):{RSRP}")
            self.RSSI_label.config(text=f"RSSI(dBm):{RSSI}")
            self.RSSNR_label.config(text=f"RSSNR(dB):{RSSNR}")
            self.Tput_label.config(text=f"Throughput(bps):{Throughput}")
            self.byte_label.config(text=f"Bytes:{Bytes}")
            
            self.root.update()
            time.sleep(1)
           
   
    def stop(self):
        global stop_measure
        stop_measure = True
        self.stop_loop = True
        self.time_label.config(text="Duration: 00:00:00")
        new_window()

            
    def quit_thread(self):
        global stop_measure
        stop_measure = True
        self.stop_loop = True
        self.time_label.config(text="Duration: 00:00:00")
        power_down(power_key)
        self.root.destroy()
        

try:   
	power_on(power_key) 
	str_current_datetime = time.strftime("%Y%m%d-%H%M%S")
	measurement_filename = str_current_datetime+".txt" #creates measurement file
	file = os.path.join(path, measurement_filename) #saves measurement file to local folder on the RPi device
	MeasurementDisplay()
	cloud_export()
	power_down(power_key)
except:
	if ser != None:
		ser.close()
	power_down(power_key)
	GPIO.cleanup()
if ser != None:
		ser.close()
		GPIO.cleanup()