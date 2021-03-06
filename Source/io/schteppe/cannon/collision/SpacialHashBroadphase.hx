package io.schteppe.cannon.collision;

import io.schteppe.cannon.math.Vec3;
import io.schteppe.cannon.objects.Body;
import io.schteppe.cannon.objects.Plane;
import io.schteppe.cannon.objects.Shape;
import io.schteppe.cannon.objects.Sphere;
import io.schteppe.cannon.utils.Pool;
import io.schteppe.cannon.world.World;

/**
 * @class CANNON.SpacialHashBroadphase
 * @brief Axis aligned uniform grid spacial hash broadphase.
 * @extends CANNON.Broadphase
 */

// FIXME: Optimize for very large shapes
// FIXME: Kinematic bodies aren't stored in the sleep hash

class SpacialHashBroadphase extends Broadphase {

    var GridBroadphase_collisionPairs_d:Vec3;
    var GridBroadphase_collisionPairs_binPos:Vec3;

    var nx:Int;
    var ny:Int;
    var nz:Int;

    var xmult:Float;
    var ymult:Float;
    var zmult:Float;
    var binRadius:Float;

    var binHash:Map<String, List<Body>>;
    var staticBinHash:Map<String, List<Body>>;
    var sleepingBinHash:Map<String, List<Body>>;

    var tempSleepingBodies:List<Body>;

    var staticBodiesHashes:Map<Body, List<String>>;
    var sleepingBodiesHashes:Map<Body, List<String>>;

    var pairHash:Map<String, Bool>;
    var planes:List<Body>;
    var bodyListPool:BodyListPool;

    var types:Dynamic;
    var SPHERE:Int;
    var PLANE:Int;
    var BOX:Int;
    var COMPOUND:Int;
    var CONVEXPOLYHEDRON:Int;

    public function new(
            nx:Int = 10,
            ny:Int = 10,
            nz:Int = 10){
        super();

        this.nx = nx;
        this.ny = ny;
        this.nz = nz;

        var nx:Float = this.nx;
        var ny:Float = this.ny;
        var nz:Float = this.nz;

        xmult = 1.0 / nx;
        ymult = 1.0 / ny;
        zmult = 1.0 / nz;
        binRadius = Math.sqrt(nx * nx + ny * ny + nz * nz) * 0.5;

        this.binHash = new Map<String, List<Body>>();
        this.staticBinHash = new Map<String, List<Body>>();
        this.sleepingBinHash = new Map<String, List<Body>>();

        this.planes = new List<Body>();
        this.pairHash = new Map<String, Bool>();
        this.bodyListPool = new BodyListPool();

        this.tempSleepingBodies = new List<Body>();
        this.sleepingBodiesHashes = new Map<Body, List<String>>();
        this.staticBodiesHashes = new Map<Body, List<String>>();

        types = Shape.types;
        SPHERE =            types.SPHERE;
        PLANE =             types.PLANE;
        BOX =               types.BOX;
        COMPOUND =          types.COMPOUND;
        CONVEXPOLYHEDRON =  types.CONVEXPOLYHEDRON;

        useBoundingBoxes = true;
        GridBroadphase_collisionPairs_d = new Vec3();
        GridBroadphase_collisionPairs_binPos = new Vec3();
    }

    public override function supportsStaticGeometry():Bool {
        return true;
    }

    /**
     * @method collisionPairs
     * @memberof CANNON.SpacialHashBroadphase
     * @brief Get all the collision pairs in the physics world
     * @param CANNON.World world
     * @param Array pairs1
     * @param Array pairs2
     */

    public override function collisionPairs(
            world:World,
            p1:Array<Body>,
            p2:Array<Body>) {
        var N:Int = world.numObjects();
        var bodies:List<Body> = world.bodies;

        var binHash = this.binHash;

        var ceil = Math.ceil;
        var min = Math.min;
        var max = Math.max;

        // Put all dynamic bodies into the bins
        for (bi in bodies) {
            /*if (bodyIsSleeping(bi)) {
                tempSleepingBodies.push(bi);
            }
            else {*/
                putBodyInBin(bi);
            //}
        }

        // store sleeping bodies
        /*for (bi in tempSleepingBodies) {
            trace("add sleeping body " + bi.id);
            bodies.remove(bi);
            var hashList:List<String> = new List<String>();
            putBodyInBin(
                    bi,
                    hashList);
            sleepingBodiesHashes.set(
                    bi,
                    hashList);
        }
        tempSleepingBodies.clear();*/

        // Check each bin
        for (key in binHash.keys()) {
            var bin:List<Body> = binHash[key];

            for (bi in bin) {
                var staticBin:List<Body> = staticBinHash[key];
                var sleepingBin:List<Body> = sleepingBinHash[key];

                for (bj in planes) {
                    if (!isAlreadyCollided(bi, bj)) {
                        if (this.needBroadphaseCollision(bi, bj)) {
                            this.intersectionTest(bi, bj, p1, p2);
                        }
                    }
                }

                if (staticBin != null) {
                    for (bj in staticBin) {
                        if (!isAlreadyCollided(bi, bj)) {
                            if (this.needBroadphaseCollision(bi, bj)) {
                                this.intersectionTest(bi, bj, p1, p2);
                            }
                        }
                    }
                }

                /*if (sleepingBin != null) {
                    for (bj in sleepingBin) {
                        if (!isAlreadyCollided(bi, bj)) {
                            if (this.needBroadphaseCollision(bi, bj)) {
                                this.intersectionTest(bi, bj, p1, p2);
                            }
                        }
                    }
                }*/

                for (bj in bin) {
                    if (bi != bj) {
                        if (!isAlreadyCollided(bi, bj)) {
                            if (this.needBroadphaseCollision(bi, bj)) {
                                this.intersectionTest(bi, bj, p1, p2);
                            }
                        }
                    }
                }
            }
        }

        for (key in pairHash.keys()) {
            pairHash.remove(key);
        }

        for (key in binHash.keys()) {
            var bodyList:List<Body> = binHash[key];
            bodyList.clear();
            bodyListPool.release(bodyList);
            binHash.remove(key);
        }
    }

    private function isAlreadyCollided(bi:Body, bj:Body):Bool {
        var id1:Int = bi.id;
        var id2:Int = bj.id;
        var idx:String = id1 < id2 ? "" + id1 + "," + id2 : "" + id2 + "," + id1;
        if (pairHash.exists(idx))
            return true;
        pairHash.set(idx, true);
        return false;
    }

    // FIXME: Add a way to remove static bodys
    public override function addStaticBody(
            bi:Body):Void {
        bi.computeAABB();
        var hashList:List<String> = new List<String>();
        putBodyInBin(
                bi,
                hashList,
                true);
        sleepingBodiesHashes.set(
                bi,
                hashList);
    }

    private function releaseSleepingBodies(key:String, bodies:List<Body>):Void {
        /*var hashes:List<String> = sleepingBodiesHashes.get(bi);

        sleepingBodiesHashes.remove(bi);
        bodies.add(bi);

        if (hashes != null) {
            for (key in hashes) {
                var bin:List<Body> = sleepingBinHash[key];
                bin.remove(bi);

                // if sleeping bin length is 0 then remove/return to pool
                if (bin.length == 0) {
                    sleepingBinHash.remove(key);
                }
            }
        }*/
    }

    private function putBodyInBin(
            bi:Body,
            hashList:List<String> = null,
            isStatic:Bool = false):Void {
        var si:Shape = bi.shape;

        switch(si.type) {
            case 1://SPHERE
                // Put in bin
                // check if overlap with other bins
                var sphere:Sphere = cast(si, Sphere);
                var x:Float = bi.position.x;
                var y:Float = bi.position.y;
                var z:Float = bi.position.z;
                var r:Float = sphere.radius;

                addBoxToBins(
                        x - r,
                        y - r,
                        z - r,
                        x + r,
                        y + r,
                        z + r,
                        bi,
                        hashList,
                        isStatic);
            case 2://PLANE:
                if (!isStatic) {
                    throw "Can't add a dynamic plane to this broadphase type.";
                }
                planes.add(bi);
            default:
                if (bi.aabbNeedsUpdate) {
                    bi.computeAABB();
                }

                addBoxToBins(
                    bi.aabbmin.x,
                    bi.aabbmin.y,
                    bi.aabbmin.z,
                    bi.aabbmax.x,
                    bi.aabbmax.y,
                    bi.aabbmax.z,
                    bi,
                    hashList,
                    isStatic);
        }
    }

    //private function bodyIsSleeping(b:Body):Bool {
    //    return !b.isAwake() && b.motionstate == 1;
    //}

    private function addBoxToBins(
            x0:Float, y0:Float, z0:Float,
            x1:Float, y1:Float, z1:Float,
            bi:Body,
            hashList:List<String> = null,
            isStatic:Bool = false):Void {
        var ceil = Math.ceil;
        var floor = Math.floor;

        var xoff0:Int = floor((x0) * xmult);
        var yoff0:Int = floor((y0) * ymult);
        var zoff0:Int = floor((z0) * zmult);
        var xoff1:Int = ceil((x1) * xmult) + 1;
        var yoff1:Int = ceil((y1) * ymult) + 1;
        var zoff1:Int = ceil((z1) * zmult) + 1;

        for (xoff in xoff0...xoff1) {
            for (yoff in yoff0...yoff1) {
                for (zoff in zoff0...zoff1) {
                    var hash:String = "#" + xoff + "#" + yoff + "#" + zoff;
                    if (hashList != null) {
                        hashList.push(hash);
                    }
                    var bins:Map<String, List<Body>>;
                    if (!isStatic) {
                        bins = binHash;// bodyIsSleeping(bi) ? sleepingBinHash : binHash;
                    }
                    else {
                        bins = staticBinHash;
                    }
                    if (bins[hash] == null) {
                        var bin:List<Body> = bodyListPool.get();
                        bin.add(bi);
                        bins[hash] = bin;
                    }
                    else {
                        bins[hash].add(bi);
                    }
                }
            }
        }
    }

}

class BodyListPool extends Pool {
    public function new() {
        super(); 
        this.type = List;
    }

    public override function constructObject():Dynamic{
        return new List<Body>();
    }
}
