"""Configure Frontier-only flags/colors (Robux) and Arsenal unlocks (Credits or Robux)."""
import argparse
import json
from pathlib import Path
import re
import urllib.request
import urllib.error
import uuid

ROOT=Path(__file__).resolve().parents[2]
UNIVERSE='10774039150'
OWNER='8318659852'


def retired_unlocks():
    source=(ROOT/'src/shared/Data/Arsenal.luau').read_text(encoding='utf-8')
    block=re.search(r'Arsenal\.RETIRED = \{([^}]+)\}',source)[1]
    return {'unlock_'+key for key in re.findall(r'(\w+)\s*=\s*true',block)}


def catalogue():
    source=(ROOT/'src/shared/Assets/ShopFlags.luau').read_text(encoding='utf-8')
    flags=re.findall(r'key = "([^"]+)", name = "([^"]+)", theme = "[^"]+", rarity = "([^"]+)"',source)
    rows=[]
    for key,name,rarity in flags:
        rows.append({'cache':key,'key':'shop_'+key,'name':'Atlas Reign Flag: '+name,
            'price':{'rare':49,'epic':99,'legendary':149}[rarity],
            'description':f'Unlock the exact {name} cosmetic flag. Robux only. No random reward or combat advantage.'})
    arsenal=(ROOT/'src/shared/Data/Arsenal.luau').read_text(encoding='utf-8').split('Arsenal.ITEMS = {',1)[1].split('} :: { Item }',1)[0]
    products=(ROOT/'src/shared/Data/Products.luau').read_text(encoding='utf-8')
    retired=retired_unlocks()
    for block in re.findall(r'\n\t\{\n(.*?)\n\t\}',arsenal,re.S):
        fields=dict(re.findall(r'^\s*(key|title|kind|product) = "([^"]+)"',block,re.M))
        if fields['product'] in retired:continue
        key=fields['product']; price=int(re.search(r'^\s*'+re.escape(key)+r' = .*?robux = (\d+)',products,re.M)[1])
        rows.append({'cache':key,'key':key,'name':'Atlas Reign Unlock: '+fields['title'],'price':price,
            'description':f"Permanent {fields['title']} unlock. Also earnable with Credits. Normal in-match Gold costs and cooldowns apply."})
    style=(ROOT/'src/shared/Data/ProfileStyle.luau').read_text(encoding='utf-8')
    colors=re.findall(r'name = "([^"]+)", rgb =',style);price=int(re.search(r'ProfileStyle.ROBUX = (\d+)',style)[1])
    for index,name in enumerate(colors[1:],2):
        if index<=6:continue # Historical ordinary colors remain owned; sell only the exclusive palette.
        key='profile_color_'+str(index)
        rows.append({'cache':key,'key':key,'name':'Atlas Reign Country Color: '+name,'price':price,
            'description':f'Unlock the exclusive {name} country color. Robux only. Cosmetic; no combat advantage.'})
    fleet=(ROOT/'src/shared/Data/FleetStyles.luau').read_text(encoding='utf-8')
    for item,name,price in re.findall(r'id="([^"]+)",name="([^"]+)",robux=(\d+)',fleet):
        rows.append({'cache':'skin_'+item,'key':'skin_'+item,'name':'Atlas Reign Livery: '+name,'price':int(price),
            'description':'Permanent '+name+' animated border and matching fleet trim. Exact cosmetic; no random reward or combat advantage.'})
    assert len(rows)==71 and len({r['key'] for r in rows})==71
    assert len(flags)==38 and len(colors)==21
    return rows


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--key-file',type=Path,required=True);args=parser.parse_args()
    api_key=args.key_file.read_text(encoding='utf-8-sig').strip()
    def call(path,data=None,content_type='application/json',method=None):
        req=urllib.request.Request('https://apis.roblox.com/'+path,data=data,headers={'x-api-key':api_key,'Content-Type':content_type},method=method)
        try:
            with urllib.request.urlopen(req,timeout=45) as response:
                body=response.read()
                return json.loads(body) if body else {}
        except urllib.error.HTTPError as e:raise RuntimeError(f'Roblox HTTP {e.code}: '+e.read().decode()[:350]) from None
    def form(path,fields,method='POST'):
        boundary=uuid.uuid4().hex
        body=''.join(f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n' for k,v in fields.items())+f'--{boundary}--\r\n'
        return call(path,body.encode(),f'multipart/form-data; boundary={boundary}',method)
    universe=call('cloud/v2/universes/'+UNIVERSE)
    assert universe.get('user')=='users/'+OWNER and universe.get('visibility')=='PRIVATE'
    rows=catalogue()
    (ROOT/'build/product-plan-v0.4.json').write_text(json.dumps(rows,indent=2)+'\n',encoding='utf-8',newline='\n')
    cache=ROOT/'assets/frontier/products.json';saved=json.loads(cache.read_text()) if cache.exists() else {}
    base=f'developer-products/v2/universes/{UNIVERSE}/developer-products'
    existing=call(base+'/creator?pageSize=100')
    assert not existing.get('nextPageToken'), 'Review pagination before configuring a larger catalogue'
    by_name={p['name']:p for p in existing['developerProducts']}
    for row in rows:
        cached=saved.get(row['cache']);product=by_name.get(row['name'],cached)
        fields={'name':row['name'],'description':row['description'],'price':str(row['price']),
                'isForSale':'true','isManagedPricingEnabled':'false'}
        if product is None:product=form(base,fields)
        elif product.get('name') != row['name'] or not product.get('isForSale') or product.get('description') != row['description'] or product['priceInformation']['defaultPriceInRobux'] != row['price']:
            product_id=product['productId']
            form(base+'/'+str(product_id),fields,'PATCH')
            product=call(base+'/'+str(product_id)+'/creator')
        assert str(product['universeId'])==UNIVERSE and product['productId']>0 and product['isForSale']
        assert product['priceInformation']['defaultPriceInRobux']==row['price']
        saved[row['cache']]=product
        cache.write_text(json.dumps(saved,indent=2)+'\n',encoding='utf-8',newline='\n')
        print(row['key'],product['productId'],row['price'],flush=True)
    retired=sorted(retired_unlocks().intersection(saved))
    retired += ['profile_color_'+str(index) for index in range(2,7)]
    for key in retired:
        product=call(base+'/'+str(saved[key]['productId'])+'/creator')
        saved[key]=product
        if product.get('isForSale'):
            form(base+'/'+str(product['productId']),{'isForSale':'False'},'PATCH')
            saved[key]=call(base+'/'+str(product['productId'])+'/creator')
        assert not saved[key]['isForSale']
    cache.write_text(json.dumps(saved,indent=2)+'\n',encoding='utf-8',newline='\n')
    # Keep historical IDs mapped so genuine pending receipts can still be fulfilled.
    rows += [{'key':key,'cache':key} for key in retired]
    text='-- Frontier-owned products; created only for universe 10774039150.\nreturn {\n'
    text+='\n'.join(f' ["{r["key"]}"]={saved[r["cache"]]["productId"]},' for r in rows)+'\n}\n'
    (ROOT/'src/shared/Data/FrontierProducts.luau').write_text(text,encoding='utf-8',newline='\n')
