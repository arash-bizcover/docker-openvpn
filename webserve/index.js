var connect = require('connect');
var http = require('http');
var app = connect();
var bodyParser = require('body-parser');
app.use(bodyParser.urlencoded({extended: false}));
const jwt = require('jsonwebtoken');
var fs = require('fs');
var path = require('path');
const { execSync } = require('child_process')
const bash = cmd => execSync(cmd, { cwd: '/tmp', shell: '/bin/bash', encoding: 'utf8', stdio: 'inherit' })

// This must be a subfolder in openvpn
const LISTEN = 3000
const CONFIG_DIR = process.env.OVPN_DATA != undefined ? `${process.env.OVPN_DATA}/ovpn-configfiles/` : "/opt/ovpn-data/ovpn-configfiles/"
const CONFIG_REF = "/tmp/get_config_file_here"
const ISSUER = process.env.ISSUER
const VALID_DOMAIN = process.env.VALID_DOMAIN
const BASH_DEBUG = `set -x`

var authorize = async(token) =>{
    try{
        if(ISSUER == undefined || VALID_DOMAIN == undefined){
            throw(`ISSUER and VALID_DOMAIN env vars should be set`)
        }
        var decoded = jwt.decode(token);
        // console.log(decoded)
        if(decoded.iss != ISSUER){
            throw(`ISSUER should be ${ISSUER}`)
        }
        if(!decoded.email.includes(VALID_DOMAIN)){
            throw(`User not recognised`)
        }
        return decoded.email
    }catch(e){
        console.error(`Athorization failed - ${e}`)
        return
    }
}

var get_config = async (user) =>{
    try{
        if(user){
            process.stdout.write(`🧑 User is: ${user}`);
            let emailobf = `${user.replace("@", "-at-")}.conf`
            bash(` set -xe; set -o pipefail;
                ${BASH_DEBUG}
                mkdir -p ${CONFIG_DIR}
                if [[ ! -f "${CONFIG_DIR}${emailobf}" ]]; then
                    docker run -v ${path.dirname(CONFIG_DIR)}:/etc/openvpn --log-driver=none --rm -it arashilmg/openvpn easyrsa build-client-full ${user} nopass
                    docker run -v ${path.dirname(CONFIG_DIR)}:/etc/openvpn --log-driver=none --rm -e OVPN_AUTH_USER_PASS=1 arashilmg/openvpn ovpn_getclient ${user} > ${CONFIG_DIR}${emailobf}
                    echo "Config file saved in ${CONFIG_DIR}${emailobf}"
                else
                    echo "🎉 File already exist no executaion"
                fi

                rm -f ${CONFIG_REF} && echo -n "${CONFIG_DIR}${emailobf}" > ${CONFIG_REF}
            `)
            let config_ref = fs.readFileSync(CONFIG_REF,'utf-8')
            return config_ref
        }
        else{
            throw("User not passed")
        }
    }catch(e){
        console.warn(`Exception in config_gen - ${e}`)
        // console.warn(e)
        return
    }
}


function fire(res) {
    res.setHeader('Content-type', 'text/html; charset=utf-8');
    res.end("<h1 style=font-size:400px><center>🔥<h1>");
    return 1;
}

// respond to all requests
app.use(async function(req, res){
    // process.stdout.write("🦰: ");
    // console.log(req.headers)
    // process.stdout.write("👕: ");
    // console.log(JSON.stringify(req.body))
    
    try {
        if(req.body.id_token){
            var email = await authorize(req.body.id_token)
        }
        else{
            throw("No id_token could be found/set!")
        }
    }catch(e){
        console.error(`❌ Auth Failed - ${e}`)
        return fire(res);
    }

    var file = await get_config(user=email)
    if(file){
        console.log(file)
        var filename = path.basename(file);
        res.setHeader('Content-type', 'text/plain; charset=utf-8');
        res.setHeader('Content-disposition', 'attachment; filename=' + filename);
        var filestream = fs.createReadStream(file);
        await filestream.pipe(res);
    }else{
        console.error("❌ File not set")
        return fire(res);
    }
    
});


//create node.js http server and listen on port
http.createServer(app).listen(LISTEN);
