function topologicalSort(graph){
  if(graph.length == 0) return [];

  var indegrees = [];
  var processed = [];
  var queue = [];

  if(populateIndegrees()) {
     processList(); 
     return processed;
  } else {
     for(var i = 0; i < graph.length; i++)
        indegrees[i] = (graph.length-i-1);
     return indegrees;
  }

  function indexOf(dep) {
    for(var i = 0; i<graph.length; i++) {
        if(graph[i].id == dep) return i;
    }
    throw new Error("Dependency not found: " + dep);
  }
 
  function processList(){
    for(var i=0; i<graph.length; i++){
      if(indegrees[i] === 0){
        queue.push(i);
        indegrees[i] = -1; //dont look at this one anymore
      }
    }
    
    processStartingPoint(queue.shift());
    if(processed.length<graph.length){
      processList();
    }
  }
  
  function processStartingPoint(i){
    if(i == undefined){
      throw new Error("You have dependency cycle");
    }
    if(graph[i].depends) graph[i].depends.forEach(function(dep){
      e = indexOf( dep );
      indegrees[e]--; 
    });
    processed.push(i);
  }
  
  function populateIndegrees(){

    var hasDeps = false;

    for(var i=0; i<graph.length; i++) indegrees[i] = 0;

    for(var i=0; i<graph.length; i++) {
        if(graph[i].depends) {
            hasDeps = true;
            graph[i].depends.forEach(function( dep ) {
                e = indexOf( dep );
                indegrees[e]++;
            }); 
        }
    }
    return hasDeps;
  }
}

exports.topologicalSort = topologicalSort;
