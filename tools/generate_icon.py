from PIL import Image, ImageDraw
import sys
N=64  # draw at 64 px, scale x16 for a crisp pixel look
img=Image.new('RGB',(N,N),(0x14,0x16,0x1C)); d=ImageDraw.Draw(img)
# sky gradient bands
bands=[(0x0B,0x0C,0x10),(0x1A,0x12,0x28),(0x3A,0x17,0x30),(0x6A,0x1E,0x45)]
for i,c in enumerate(bands): d.rectangle([0,i*6,N,i*6+5],fill=c)
# sun
for r,c in [(16,(0xFF,0x8A,0x3D)),(13,(0xFF,0x6A,0x6A)),(10,(0xFF,0x3E,0xA5))]: pass
d.ellipse([16,6,48,38],fill=(0xFF,0x8A,0x3D)); d.rectangle([16,22,48,38],fill=(0xFF,0x3E,0xA5))
for y in (26,30,34): d.rectangle([14,y,50,y],fill=(0x3A,0x17,0x30))
# skyline
hs=[10,16,12,20,14,22,11,18]
for i,h in enumerate(hs):
    x=i*8; d.rectangle([x,34-h+12,x+7,40],fill=(0x0B,0x0C,0x10)); d.rectangle([x,34-h+12,x+7,34-h+12],fill=(0x2E,0xE6,0xD6) if i%2 else (0xFF,0x3E,0xA5))
# road
d.rectangle([0,40,N,N],fill=(0x14,0x16,0x1C))
for x in range(2,N,10): d.rectangle([x,51,x+5,52],fill=(0xF4,0xEB,0xD9))
# car (from the game sprite, nose up)
rows=["....cccccc....","...cmmmmmmc...","..mmmmmmmmmm..",".kmmmmmmmmmmk.",".kmmttttttmmk.",".kmttttttttmk.","..mttttttttm..","..mmmmmmmmmm..","..mmwmmmmwmm..","..mmwmmmmwmm..","..mmmmmmmmmm..","..mtttttttm...","..mttttttttm..",".kmmmmmmmmmmk.",".kmmmmmmmmmmk.","..mmmmmmmmmm..","...ommmmmmo...","...oo....oo..."]
pal={'m':(0xFF,0x3E,0xA5),'t':(0x2E,0xE6,0xD6),'c':(0xF4,0xEB,0xD9),'o':(0xFF,0x8A,0x3D),'k':(0x0B,0x0C,0x10),'w':(0xC0,0x2A,0x7C)}
ox,oy=25,44
for y,row in enumerate(rows):
    for x,ch in enumerate(row):
        if ch in pal: img.putpixel((ox+x,oy+y) if oy+y<N else (0,0),pal[ch])
img=img.resize((1024,1024),Image.NEAREST); img.save(sys.argv[1])
