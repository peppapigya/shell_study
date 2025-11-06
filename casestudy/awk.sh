#!/bin/bash

analyse_ip(){
  awk '{
     map[$1]++
  }
  END{
  count=0
  for (key in map){
    if (map[key]<=1000){
      continue
    }

    arr[count++]=sprintf("%d \t %s",map[key],key)
  }
  asort(arr,sorted,"@val_num_desc")
  for (i in sorted){
      print sorted[i]
  }
}' /peppapig/access.log

 awk '{
     map[$1]++
  }
  END{
  asort(map)
  for (key in map){
    print key,map[key]
  }
}' /peppapig/access.log
}