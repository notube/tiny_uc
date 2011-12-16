


function Bonjour(){
    
}


Bonjour.prototype.nativeFunction = function(success, fail, str) {
    //alert("foo");
    var types=["HelloWorld"];
    var rr ;
    try{
        rr = PhoneGap.exec(success, fail, "Bonjour", "print", types);
    }catch(ex){
        alert("boo");
    }
    
    return rr;
}
    


