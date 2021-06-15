import matplotlib.pyplot as plt
import numpy as np
import json

space = 0
data = []

with open('sd_contents2.txt','r') as raw_data:
    lines = raw_data.readlines()

sd_data = open('sd_data.txt','w')

for index,char in enumerate(lines[2]):
    if char == ' ':
        space = index + 1
        break   
        
for line in lines[2:]:
    index = space + 1
    bytes = 0
    while bytes<16:
        reading = ''.join([line[index],line[index + 1]])

        data.append(int(reading,16))
        index += 3
        bytes += 1
        
json.dump(data,sd_data)
sd_data.close()

plt.plot(data)
plt.show()
