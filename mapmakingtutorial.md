# tutorial jak delat mapu aby fungoval ten fading a jak spravne proste zachazet se s temi vrstvy

## 1. pozadi
<img width="2071" height="1855" alt="image" src="https://github.com/user-attachments/assets/4a8569b5-b596-4482-ac2b-e4d0a38547a3" />
1.1 v tilemapbase nejdriv nakreslis vsechny tily ktere jsou na uplnem pozadi a nevyzadujes aby byli nejak dynamicke. 
tj. napr. podlaha, nejvzdalenejsi zed(ze kterou se character nikdy nemuze dostat), a perimeter(zleva a zprava kde nemas zadny fading a nevidis to ze strany ale jenom zeshora.)
docela dulezity moment - musis se pocitat s tim ze delas v perspektive, tak ze napriklad tady, cela podlaha bude zakryta tou fading zdi kterou udelame






## 2. zed s fadingem
### 2.1. pod world after render vytvoris tilemaplayer nodu.
pro pohodli pojmenuju nejak "foreground_tun1_southwall"
<img width="2405" height="1396" alt="image" src="https://github.com/user-attachments/assets/829b94ce-e8a7-4dea-8eed-136d17b2203a" />

### 2.2. nakreslis na nem south zed na ktere se bude objevovat fading

<img width="953" height="763" alt="image" src="https://github.com/user-attachments/assets/60b87b5b-0703-4954-953f-c8f4e2f4de79" />

## 3. trigger pro fading
### 3.1
pod world after render pridas novou area2d nodu(tunnel_fade_trigger)
### 3.2
pridas mu child collisionshape2d rectangel(trigger shape), zona kde ten fading zacne fungovat. nastavis pozici a rozmer aby +- pokryval celou tu zed.
<img width="1954" height="924" alt="image" src="https://github.com/user-attachments/assets/ca9583d5-3d59-4109-842d-1879690eb845" />
### 3.3
u area2d pridas ten wallfade script
<img width="2504" height="1463" alt="image" src="https://github.com/user-attachments/assets/05f11734-ff57-4e3f-9589-bba9a53ee9d1" />
### 3.4 nastaveni area2d
<img width="2625" height="1889" alt="image" src="https://github.com/user-attachments/assets/3e799f9b-cd74-4147-8116-cf94c4d71acd" />
target wall = ten tilemap zdi u ktere bude fading
collision layer = 0(je to jenom sensor, zadny collision nechceme)
collision mask = 2

## 4. pridani archu
tilearchoverlay tilemap s z indexem 2. vzdy on top vseho.
<img width="2191" height="1108" alt="image" src="https://github.com/user-attachments/assets/1b1aa95b-f51a-48be-82ee-d19eab85b1eb" />


## 5. pridani collison borderu 
pridani collision borderu, jednoduche colission shape 2d rect
<img width="2565" height="1260" alt="image" src="https://github.com/user-attachments/assets/279173af-167b-424d-82fc-2e3a4d856bae" />

p.s. pri napsani setkal jsem se s problemem a kvuli tomu musel vytvorit 2. layer u fading zdi - protoze potrebuji aby cast zdi byla na vyssim layeru nez tilemapbase(protoze je blizsi ke kamere nez napr podlaha) ale zaroven zed perimetru byla nad bocnimy cihlami te zdi. asi exuistuje lepsi zpusob jak to udelat ale whatever. dole obrazek se vsemi z-indexy
<img width="2075" height="1278" alt="image" src="https://github.com/user-attachments/assets/41df9d21-83b7-4ebd-8628-6501e9b8adc1" />

tldr. ten fading script implicitne seskupuje vsechny child elementy hlavni fading zdi.

tady je popsano jak bys se mel zachazet s tily, kdyz mas ten perimeter wall ktery ma jenom polovicky delku a zbytek je pruhledny.
<img width="924" height="521" alt="image" src="https://github.com/user-attachments/assets/d34f1fd1-a125-4795-a373-92a433bb762d" />


## 6. hotovo
postavicka se krasne ukazuje za zdi
<img width="1487" height="1159" alt="image" src="https://github.com/user-attachments/assets/e6d4e811-ae86-4bc6-a411-0de37e0209ce" />
