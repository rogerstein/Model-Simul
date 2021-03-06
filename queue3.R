#reproduz sistema de fila com n servos baseado em dados coletados
options(stringsAsFactors = FALSE)

queue <- 
  data.frame(
    clientNum <- numeric(),
    arrivalTime <- numeric(),
    chamada <- character(),
    stringsAsFactors = F
  )

data <- read.csv(file="dataNoite.csv", stringsAsFactors = F)
data$arrivalTimestamp <- as.POSIXct(data$arrivalTimestamp)
data$servStartTimestamp <- as.POSIXct(data$servStartTimestamp)

#state variables
clientNum <- 1
timeNextArrival <- data[clientNum, "arrivalTimestamp"]
timeNextDeparture <- Inf # just to make shure the first event is an arrival
simClock <- timeNextArrival - 1
numCustServed <- 0

#statistics
delaysTotal <- 0
delay <- 0
areaQ <- 0
areaB <- 0
numDelayedCustomers <- 0

#stop criteria (number of served customers)
reqCustServed <- nrow(data)

update <- function(curTime, event){
  timeLast <<- simClock
  simClock <<- curTime
  diffTime <- as.numeric(curTime) - as.numeric(timeLast)
  areaQ <<- areaQ + nrow(queue) * diffTime
  areaB <<- areaB + diffTime * sum(servers$busy)
}

logDF <- data.frame()
log <- function(event, clientNum, chamada){
  logDF <<- rbind(logDF, 
                  data.frame(time=as.POSIXct(simClock, origin = "1970-01-01"), 
                             type=event, 
                             clientNum=clientNum,
                             chamada=chamada,
                             busyServers=sum(servers$busy), 
                             queueSize=nrow(queue),
                             numDelayed = numDelayedCustomers,
                             numServed = numCustServed,
                             cumD = delaysTotal,
                             cumQ = areaQ, 
                             cumB = areaB
                             ))}

numServers <- 9
servers <- 
  data.frame(
    busy=rep(FALSE, numServers),
    depTime=Inf,
    clientNum=0,
    chamada="",
    stringsAsFactors = F
  )

allServersBusy <- function(){
  as.logical(sum(servers$busy)==nrow(servers))
}

allocateServer <- function(clientNum, chamada) {
  choosenServer <-
    if(length(which(!servers$busy))==1) 
      which(!servers$busy) 
    else 
      sample(which(!servers$busy), 1)
  servers[choosenServer, ] <<- list(busy=T, 
                                    depTime=getDepartTime(clientNum), 
                                    clientNum=clientNum, 
                                    chamada=chamada)
}

deallocateServer <- function(server) {
  servers[server, ] <<- list(FALSE, Inf, 0, "")
}

getDepartTime <- function(clientNum) {
  simClock + data[clientNum, "servDuration"]
}

log("start", 0, chamada="")
while(numCustServed < reqCustServed){
  if(timeNextArrival < as.POSIXct(timeNextDeparture, origin = "1970-01-01")){
    update(timeNextArrival, "arrival")
    arrivingClient <- clientNum
    chamada <- data[arrivingClient, "Chamada"]
    if(allServersBusy()){
      if(substr(chamada, 2, 2)=="P"){
        #customer goes to start of the queue
        queue <- rbind(data.frame(clientNum=arrivingClient, 
                                  arrivalTime=simClock, 
                                  chamada=chamada), 
                       queue)      
      } else {
        #customer goes to end of the queue
        queue <- rbind(queue, 
                       data.frame(clientNum=arrivingClient, 
                                  arrivalTime=simClock, 
                                  chamada=chamada))
      }
    } else {
      allocateServer(clientNum, chamada)
      timeNextDeparture <- min(servers$depTime)
      serverNextDeparture <- which.min(servers$depTime)
    }
    log("arrive", arrivingClient, chamada=chamada)
    clientNum <- clientNum + 1
    timeNextArrival <- if (is.na(data[clientNum, "arrivalTimestamp"])) Inf else data[clientNum, "arrivalTimestamp"]
  }else{
    update(timeNextDeparture, "departure")
    departingClientNum <- servers[serverNextDeparture, "clientNum"]
    departingClientChamada <- servers[serverNextDeparture, "chamada"]
    deallocateServer(serverNextDeparture)
    numCustServed <- numCustServed + 1
    if(nrow(queue)>0){
      delay <- simClock - as.numeric(queue[1, "arrivalTime"])
      delaysTotal <- delaysTotal + delay
      allocateServer(clientNum=queue[1, "clientNum"], chamada=queue[1, "chamada"])
      numDelayedCustomers <- numDelayedCustomers + 1
      queue <- queue[-1,]
    }
    timeNextDeparture <- min(servers$depTime)
    serverNextDeparture <- which.min(servers$depTime)
    log(event="depart", clientNum=departingClientNum, chamada=departingClientChamada)
  }
}

write.csv2(logDF, file = "logRepNoite.csv", row.names = FALSE)
#logDF <- read.csv2(file = "logRepNoite.csv")

#library(ggplot2)
#ggplot() + geom_step(data=logDF, mapping=aes(x=time, y=queueSize))

library(plyr)
summary18 <-
  ddply(logDF[format(logDF$time, "%H")=="18",], 
      .(date=format(time, "%y-%m-%d")), 
      function(x) c(QsizeAtStart=x[which.min(x$time), "queueSize"], 
                    busySrvAtStart=x[which.min(x$time), "busyServers"],
                    #deltaD=x[which.max(x$time), "cumD"] - x[which.min(x$time), "cumD"],
                    deltaServed=x[which.max(x$time), "numServed"] - x[which.min(x$time), "numServed"],
                    avgD=(x[which.max(x$time), "cumD"] - x[which.min(x$time), "cumD"])/(x[which.max(x$time), "numServed"] - x[which.min(x$time), "numServed"]),
                    #deltaQ=x[which.max(x$time), "cumQ"] - x[which.min(x$time), "cumQ"],
                    avgQ=(x[which.max(x$time), "cumQ"] - x[which.min(x$time), "cumQ"])/(60*60),
                    #deltaB=x[which.max(x$time), "cumB"] - x[which.min(x$time), "cumB"],
                    avgU=(x[which.max(x$time), "cumB"] - x[which.min(x$time), "cumB"])/(60*60*numServers),
                    minTime=min(x$time),
                    maxTime=max(x$time)))
summary18$minTime <- as.POSIXct(summary18$minTime, origin = "1970-01-01")
summary18$maxTime <- as.POSIXct(summary18$maxTime, origin = "1970-01-01")

write.table(summary18, file = "summaryRep18.csv", sep = ",", dec = ".", row.names = FALSE, eol = "\r")

summary20 <-
  ddply(logDF[format(logDF$time, "%H")=="20",], 
        .(date=format(time, "%y-%m-%d")), 
        function(x) c(QsizeAtStart=x[which.min(x$time), "queueSize"], 
                      busySrvAtStart=x[which.min(x$time), "busyServers"],
                      #deltaD=x[which.max(x$time), "cumD"] - x[which.min(x$time), "cumD"],
                      deltaServed=x[which.max(x$time), "numServed"] - x[which.min(x$time), "numServed"],
                      avgD=(x[which.max(x$time), "cumD"] - x[which.min(x$time), "cumD"])/(x[which.max(x$time), "numServed"] - x[which.min(x$time), "numServed"]),
                      #deltaQ=x[which.max(x$time), "cumQ"] - x[which.min(x$time), "cumQ"],
                      avgQ=(x[which.max(x$time), "cumQ"] - x[which.min(x$time), "cumQ"])/(60*60),
                      #deltaB=x[which.max(x$time), "cumB"] - x[which.min(x$time), "cumB"],
                      avgU=(x[which.max(x$time), "cumB"] - x[which.min(x$time), "cumB"])/(60*60*numServers),
                      minTime=min(x$time),
                      maxTime=max(x$time)))
summary20$minTime <- as.POSIXct(summary20$minTime, origin = "1970-01-01")
summary20$maxTime <- as.POSIXct(summary20$maxTime, origin = "1970-01-01")

write.table(summary20, file = "summaryRep20.csv", sep = ",", dec = ".", row.names = FALSE, eol = "\r")

highDays <- intersect(summary18[summary18$avgU>0.9,"date"], summary20[summary20$avgU>0.9,"date"])

#summary18 <- read.csv2(file = "summaryRep18.csv", stringsAsFactors = F)
#summary18[,4:6] <- apply(summary18[,4:6], 2, as.numeric)

apply(summary18[summary18$date %in% highDays, sapply(summary18, is.numeric)], 2, mean)
apply(summary18[summary18$date %in% highDays, sapply(summary18, is.numeric)], 2, sd)
 hist(summary18[summary18$date %in% highDays, "deltaServed"])

apply(summary20[summary20$date %in% highDays, sapply(summary20, is.numeric)], 2, mean)
apply(summary20[summary20$date %in% highDays, sapply(summary20, is.numeric)], 2, sd)
 hist(summary20[summary20$date %in% highDays, "deltaServed"])





