/**
 * format.js
 */

fs = require('fs');

var file_str = fs.readFileSync('LeNet-model');
var file_json = JSON.parse(file_str);

var i;
var layer_value;

layer_value = file_json.value0;
extract(0, layer_value);

//layer_value = file_json.value1;
//extract(1, layer_value);

layer_value = file_json.value2;
extract(2, layer_value);

//layer_value = file_json.value3;
//extract(3, layer_value);

layer_value = file_json.value4;
extract(4, layer_value);

layer_value = file_json.value5;
extract(5, layer_value);
/*
for (i = 0; i < weights.length; i++) {
    //console.log(weights[i]);
    fs.appendFileSync(file_wt_str, weights[i]);
    fs.appendFileSync(file_wt_str, '\n');
}
*/

function extract(layer, layer_value)
{
    var i;
    var file_wt_str;
    var file_bs_str;
    var weights = layer_value.value0;
    var biases = layer_value.value1;

    file_wt_str = 'layer' + layer + '.wt';
    file_bs_str = 'layer' + layer + '.bs';
    for (i = 0; i < weights.length; i++) {
        fs.appendFileSync(file_wt_str, weights[i]);
        fs.appendFileSync(file_wt_str, '\n');
    }
    for (i = 0; i < biases.length; i++) {
        fs.appendFileSync(file_bs_str, biases[i]);
        fs.appendFileSync(file_bs_str, '\n');
    }
}
