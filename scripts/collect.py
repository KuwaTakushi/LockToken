import asyncio
import time
from lockTokenABI import LOCK_TOKEN_ABI
from web3 import Web3
import os
import json

contract_address = "0xCF48bDf434201EE71c78b293AD879a3e3Ff0E54e"
fiflter_lock_user_list = []

def prepare_client_and_instance(rpc: str):
    if rpc:
        abi = LOCK_TOKEN_ABI
        w3 = Web3(Web3.WebsocketProvider(rpc)) if "wss" in rpc else Web3(Web3.HTTPProvider(rpc))
        contract_instance = w3.eth.contract(address=contract_address, abi=abi)
        return contract_instance

def read_fiflter_lock_user() -> list:
    current_directory = os.getcwd()
    json_files = [file for file in os.listdir(current_directory) if file.endswith('.json')]
    for file in json_files:
        with open(os.path.join(current_directory, file), 'r') as f:
            data_array = json.load(f)['fiflter']
            return data_array

def check_fiflter_lock_user(fiflter_user: str, fiflter_postion_start_at: int) -> bool:
    for data in fiflter_lock_user_list:
        address, info = data['address'], data['info']
        if fiflter_user in address and len(info) > 0:
            for t in info:
                if fiflter_postion_start_at == int(t['lockerStartTime']):
                    return True
                else:
                    return False

def collect_lock_token_slot(contract_instance):
    try:
        count = contract_instance.functions.getAllUsersCount().call()
        lock_token_user_info_list = []
        if count:
            for i in range(1000, count):
                print(f"############################ RUNNING INDEX {i} ############################")
                user_address = contract_instance.functions.getUser(i).call()
                user_info = contract_instance.functions.getUserDetails(user_address).call()
                user_token_situation = user_info[2]
                if user_token_situation:
                    total_sum = 0
                    total_locking_size = 0
                    total_amount_fromwei = 0
                    try:
                        lock_token_user_info = {}
                        for tup in user_token_situation:
                            locking_start_at = tup[4]
                            is_fiflter_postion = check_fiflter_lock_user(user_address, locking_start_at)
                            print("is_fiflter_postion", is_fiflter_postion)
                            if not is_fiflter_postion or is_fiflter_postion is None:
                                locking_status = tup[2]
                                if locking_status == 2:
                                    total_sum += Web3.from_wei(tup[-2], 'ether')
                                    total_locking_size += 1
                                    total_amount_fromwei += tup[-2]

                                    lock_token_user_info['index'] = i
                                    lock_token_user_info['user'] = user_address
                                    lock_token_user_info['lockingSize'] = total_locking_size
                                    lock_token_user_info['lockingAmount'] = float(total_sum)
                                    lock_token_user_info['lockingAmountFromWei'] = total_amount_fromwei
                                    
                        if lock_token_user_info:
                            print(lock_token_user_info)
                            lock_token_user_info_list.append(lock_token_user_info)
                    except:
                        pass
                    
        with open('lock_token_user_info.json', 'w') as json_file:
            json.dump(lock_token_user_info_list, json_file, indent=4)
        print("===========================================================================================")
        print("================================== SUCCESSED RECORD USER ==================================")
        print("===========================================================================================")
    except:
        pass
    
def main():
    global fiflter_lock_user_list
    fiflter_lock_user_list = read_fiflter_lock_user()
    
    contract = prepare_client_and_instance("wss://bsc.publicnode.com")
    collect_lock_token_slot(contract)
            
if __name__ == "__main__":
    main()

    
'''
{
    'user': '0x21F82EE58b72EEd7C309D602d60686A13585294d', 
    'tokenSituation': [
        (2, 1, 1, 0, 1697179254, 1699771254, 160000000000000000, 0), 
        (1, 1, 1, 1699771707, 1697179707, 1712731707, 4900000000000000000, 4900000000000000000), 
        (2, 1, 1, 0, 1697180515, 1699772515, 7800000000000000000, 0), 
        (2, 1, 1, 0, 1697180554, 1699772554, 10000000000000000, 0), 
        (2, 1, 1, 0, 1697180591, 1699772591, 10000000000000000, 0), 
        (2, 1, 1, 0, 1697180627, 1699772627, 10000000000000000, 0), 
        (2, 1, 1, 0, 1697180661, 1699772661, 12800000000000000, 0), 
        (2, 1, 1, 0, 1697181991, 1699773991, 3000000000000000000, 0), 
        (1, 1, 1, 1699779049, 1697187049, 1712739049, 8000000000000000000, 8000000000000000000), 
        (2, 1, 1, 0, 1697187676, 1699779676, 1000000000000000000, 0), 
        (2, 1, 1, 0, 1697198866, 1699790866, 976000000000000000, 0), 
        (1, 1, 1, 1699790908, 1697198908, 1712750908, 1000000000000000000, 1000000000000000000)]
    }


('0xd3e5d656C081f86A3776DCdC909607Cea9eBb111', 
(1, '0x3d99A6CeCBd8d50587A541ff099C0337D5fEB5De', '0x34614422AD3A81F6E5594DA611aB14bBB534C3FB', 0), 
[(1, 1, 1, 1704942779, 1697166779, 1712718779, 6000000000000000000000, 6000000000000000000000), (2, 1, 1, 0, 1698123809, 1700715809, 320000000000000000000, 0), 
(2, 1, 1, 0, 1700704192, 1703296192, 2000000000000000000000, 0), (2, 1, 1, 0, 1700833339, 1703425339, 1000000000000000000000, 0), (2, 1, 1, 0, 1703139079, 1705731079, 2100000000000000000000, 0)], 
['0xa4a1ba3646d5EbbbBddAa2C660D7a68a3dFd9802'])
'''
    
