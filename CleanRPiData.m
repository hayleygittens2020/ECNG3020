[files,path] = uigetfile('*.txt',  'Select TXT files','MultiSelect','on'); %selecting multiple nmf files
if iscell(files) == 0  %checks if the files variable is a cell, if not a cell it turns the variable into a cell
    files = {files};
end

exportfileID = fopen('rpi_data_export.csv','wt');
for a=1:length(files)
    filename = files{a};
    importfileID = fopen([path filename]);
    numLines = linesInFile(importfileID);
    
    check = {'+CGPSINFO:','+CPSI:','+Data:'};
    
    readRpiWaitBar = waitbar(0, 'Starting','Name',['Extracted lines from each file ', strjoin(check,'|')]);%https://www.mathworks.com/matlabcentral/answers/599287-progress-bar-and-for-loop
    tic
    for b= 1:numLines
        tline = fgetl(importfileID);%https://www.mathworks.com/matlabcentral/answers/22289-read-an-input-file-process-it-line-by-line
        fprintf(exportfileID, [tline,'\n']);
     waitbar(b/numLines, readRpiWaitBar, sprintf('Data Extraction Progress: %d %%', floor((b/numLines)*100)));
    end

    toc
    close(readRpiWaitBar);
end
fclose(importfileID);
fclose(exportfileID);
clearvars -except check

%% Importing extracted data into MATLAB struct
extractedfileID = fopen('rpi_data_export.csv', 'rb');    
measurements.rawdata = cell(1,3);
NumCGPS = 0;
NumCPSI = 0;
NumData = 0;

extractedNumLines = linesInFile(extractedfileID);
extractedDataMATLABImport= waitbar(0, 'Starting','Name',['File Imported Tags - ', strjoin(check,'|')]);
for i= 1:extractedNumLines
    tline = fgetl(extractedfileID);
    if tline ~= -1
        if ~isempty(regexp(tline,'+CGPS', 'once'))
            NumCGPS = NumCGPS +1;
            measurements.rawdata{NumCGPS,1} = tline;
            measurements.rawdata{NumCGPS,2} = '';
            measurements.rawdata{NumCGPS,3} = '';
            NumCPSI = 0;
            NumData = 0;

        end
        if ~isempty(regexp(tline,'+CPSI', 'once'))
            NumCPSI = NumCPSI +1;
            measurements.rawdata{NumCGPS,2}{NumCPSI,1} = tline;
        end
        if ~isempty(regexp(tline,'+Data', 'once'))
            NumData = NumData +1;
            measurements.rawdata{NumCGPS,3}{NumData,1} = tline;
        end
     end
      waitbar(i/extractedNumLines, extractedDataMATLABImport, sprintf('MATLAB Import Progress: %d %%', floor((i/extractedNumLines)*100)));
end
    [measurements.NumCGPS, ~] = size(measurements.rawdata);
    close(extractedDataMATLABImport)
    fclose(extractedfileID);
    clearvars -except measurements

%% GPS Data
data = cell(1,4);
ASTtime = 0;
rem = 0;
for x = 1:measurements.NumCGPS
   GPSline = measurements.rawdata{x,1};
   splitrow = strsplit(GPSline,':');
   newGPSline = splitrow{1,2};
   errorstr = ',,,,,,,,"';
   tf = strcmp(newGPSline,errorstr);
   if tf == 1
       continue
   else
       splitGPSline = strsplit(newGPSline,',');
       % Time
       UTCtime = str2double(splitGPSline{1,6});
       if UTCtime >= 40000
           ASTtime = UTCtime - 40000;  %converting to atlantic standard time
           if ASTtime < 10000
               temp_string = str(ASTtime);
               ASTtime = "00"+ temp_string;
           elseif ASTtime < 100000
               temp_string = str(ASTtime);
               ASTtime = "0"+ temp_string;
           end
       else
           rem = 40000 - UTCtime;     
           ASTtime = 240000 - rem;
       end
       strTime = num2str(ASTtime);
       tempTime = sprintf('%c%c:%c%c:%c%c',strTime);
       data{x,1} = tempTime;

       % Converting latitude 
       latitude = string(splitGPSline{1,1});
       splitLat = split(latitude,"");
       if length(splitLat) < 12
           continue
       else
           latLine = splitLat(2) + splitLat(3);
           smallLat = splitLat(4)+splitLat(5)+splitLat(6)+splitLat(7)+splitLat(8)+splitLat(9)+splitLat(10)+splitLat(11)+splitLat(12);
           NorthOrSouth = splitGPSline{1,2};
       end

       longitude = string(splitGPSline{1,3});
       splitLong = split(longitude,"");
       if length(splitLong) < 13
           continue
       else
       longLine = splitLong(2) + splitLong(3) +splitLong(4);
       smallLong = splitLong(5)+splitLong(6)+splitLong(7)+splitLong(8)+splitLong(9)+splitLong(10)+splitLong(11)+splitLong(12)+splitLong(13);
       EastOrWest = splitGPSline{1,4};
   
       FinalLat = str2double(latLine) + ((str2double(smallLat))/60);
       FinalLong = str2double(longLine) + ((str2double(smallLong))/60);
   
           if NorthOrSouth == 'S' 
               FinalLat = -FinalLat;
           end
           if EastOrWest == 'W'
               FinalLong = -FinalLong;
           end

           data{x,2} = FinalLat;
           data{x,3} = FinalLong;

% Speed/Velocity
        speedKnots = str2double(splitGPSline{1,8});
        knotsConvert = 1.852*(1000/3600);
        speed = speedKnots * 0.51444 * knotsConvert;
        data{x,4} = speed;
       end
   end

 
% System UE measurements 
   Mline = measurements.rawdata{x,2};
   if Mline == ""
       continue
   else
   Measline = Mline{1,1};
   splitrow = strsplit(Measline,':');
   newMeasline = splitrow{1,2};
   splitMeasline = strsplit(newMeasline,',');
   if length(splitMeasline) < 14
       continue
   else
       if str2double(splitMeasline{1,6}) < 0 
           data{x,5} = 0;
       else
           data{x,5} = str2double(splitMeasline{1,6}); %PcellID
       end
       tempBand = strsplit(splitMeasline{1,7},'D');
       if str2double(tempBand{1,2}) == 2 || str2double(tempBand{1,2}) == 28 || str2double(tempBand{1,2}) == 4
           data{x,6} = str2double(tempBand{1,2}); %Frequency band
       else
           data{x,6} = 0;
       end
           data{x,7} = str2double(splitMeasline{1,8}); %EARFCN
           data{x,8} = str2double(splitMeasline{1,11})*0.1; %RSRQ
           data{x,9} = str2double(splitMeasline{1,12})*0.1; %RSRP
           data{x,10} = str2double(splitMeasline{1,13})*0.1; %RSSI
       %RSSNR
       temp = split(splitMeasline{1,14},'"');
       data{x,11} = str2double(temp{1}); 
   end
   end
% Data Measurement
   Dline = measurements.rawdata{x,3};
   if Dline == "" 
       continue
   else
       Dataline = Dline{1,1};
       splitrow = strsplit(Dataline,':');
       if length(splitrow) < 4
           continue
       else
           newDataline = splitrow{1,4};
           splitDataline = strsplit(newDataline,',');
           if length(splitDataline) < 4
               continue
           else
               tempData = strsplit(splitDataline{1,4},'"');   
               data{x,12} = str2double(tempData{1});
               data{x,13} = str2double(splitDataline{1,2});
           end 
       end
   end
end

datatemp = data;
for col = 1:width(datatemp)
    for x = 1:size(datatemp)
        if datatemp{x,col} ~= 0
            continue 
        else
            for y = 1:width(datatemp)
                datatemp{x,y} = [];
            end
        end
    end
end

cleanData = datatemp(~all(cellfun(@isempty,datatemp),2),:);
T = array2table(cleanData);
T.Properties.VariableNames(1:13) = {'Time', 'Latitude', 'Longitude', 'Velocity', 'PCI', 'Frequency Band', 'EARFCN','RSRP','RSSI','RSRQ','RSSNR','Throughput', 'Bytes'};

writetable(T,'RPiDriveTest.xlsx', 'Sheet',1)

Test = RPiDriveTest;
%% Zone1
Zone1 = zeros();
s = 1;

for x = 1:size(Test,1)
    latZone1 = Test{x,2};
    longZone1 = Test{x,3};%-61.4052 10.646789
    if ((latZone1 >=  10.63701 && latZone1 <= 10.646523) && (longZone1 >= -61.402497  && longZone1 <= -61.396876))
        for y = 1: width(Test) 
            Zone1(s,y) = Test{x,y};
        end
        s = s+1;
    else
        continue
    end
end

figure
geobasemap streets
title 'Zone 1'
hold on 
for x = 1:length(Zone1)
    g = geoplot(Zone1(x,2),Zone1(x,3),'k', 'Marker','o',MarkerFaceColor='b', MarkerEdgeColor='b' ,MarkerSize=3);
end


%% Zone2

Zone2 = zeros();
s = 1;

for x = 1:size(Test,1)
    latRoad = Test{x,2};
    longRoad = Test{x,3};  
    if ((latRoad >=  10.645115 && latRoad <= 10.652963) && (longRoad >= -61.407567 && longRoad <= -61.394299))
        for y = 1: width(Test) 
            Zone2(s,y) = Test{x,y};
        end
        s = s+1;
    end
end

figure
geobasemap streets
title 'Zone 2'
hold on

for x = 1:length(Zone2)
    r = geoplot(Zone2(x,2),Zone2(x,3),'k', 'Marker','o',MarkerFaceColor='b', MarkerEdgeColor='b' ,MarkerSize=3);
end

clearvars 


%% Zone3 
Zone3 = zeros();
s = 1;

for x = 1:size(Test,1)
    latZone3 = Test{x,2}; 
    longZone3 = Test{x,3}; 
    if ((latZone3 >= 10.652400 && latZone3 <= 10.658521) && (longZone3 >= -61.405294  && longZone3 <= -61.399023))
        for y = 1: width(Test) 
            Zone3(s,y) = Test{x,y};
        end
        s = s+1;
    end
end

figure
geobasemap streets
title 'Zone 3'
hold on

for x = 1:length(Zone3)
    sm = geoplot(Zone3(x,2),Zone3(x,3),'k', 'Marker','o',MarkerFaceColor='b', MarkerEdgeColor='b' ,MarkerSize=3);
end

%% Zone4
Zone4 = zeros();
s = 1;

for x = 1:size(Test,1)
    latZone4 = Test{x,2};  
    longZone4 = Test{x,3};  %10.651879
    if ((latZone4 >= 10.645438 && latZone4<=  10.6632) && (longZone4 >= -61.397082  && longZone4 <= -61.391774))
        for y = 1: width(Test) 
            Zone4(s,y) = Test{x,y};
        end
        s = s+1;
    end
end

figure
geobasemap streets
title 'Zone 4'
hold on 

for x = 1:length(Zone4)
    m = geoplot(Zone4(x,2),Zone4(x,3),'k', 'Marker','o',MarkerFaceColor='b', MarkerEdgeColor='b' ,MarkerSize=3);
end


-except RPiSunDriveTest Zone1 Zone2 Zone3 Zone4 Test
